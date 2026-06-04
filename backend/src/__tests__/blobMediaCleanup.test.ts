// Regression test for C2 (security audit 2026-06-04): video blobs were
// orphaned by every delete path because cleanup deleted only blob_path +
// thumbnail_blob_path. deleteMediaAssets must prefix-delete the per-video
// directory (HLS segments + fallback + poster), and still delete original +
// thumb for photo rows.

const deletedBlobs: string[] = [];
const listedPrefixes: string[] = [];

// Simulated blobs that exist in the container for prefix-list to enumerate.
const containerBlobs = [
  'photos/c1/e1/vid1/original.mp4',
  'photos/c1/e1/vid1/hls/manifest.m3u8',
  'photos/c1/e1/vid1/hls/segment_000.ts',
  'photos/c1/e1/vid1/hls/segment_001.ts',
  'photos/c1/e1/vid1/fallback.mp4',
  'photos/c1/e1/vid1/poster.jpg',
  // A sibling video whose id is a prefix-superset — must NOT be touched.
  'photos/c1/e1/vid1x/original.mp4',
  'photos/c1/e1/p1/original.jpg',
  'photos/c1/e1/p1/thumb.jpg',
];

jest.mock('@azure/identity', () => ({
  DefaultAzureCredential: jest.fn(() => ({})),
}));

jest.mock('@azure/storage-blob', () => ({
  BlobServiceClient: jest.fn(() => ({
    getContainerClient: () => ({
      deleteBlob: (name: string) => {
        deletedBlobs.push(name);
        return Promise.resolve();
      },
      getBlockBlobClient: (name: string) => ({
        deleteIfExists: () => {
          deletedBlobs.push(name);
          return Promise.resolve();
        },
      }),
      listBlobsFlat: ({ prefix }: { prefix: string }) => {
        listedPrefixes.push(prefix);
        const matches = containerBlobs.filter((b) => b.startsWith(prefix));
        return {
          async *[Symbol.asyncIterator]() {
            for (const name of matches) yield { name };
          },
        };
      },
    }),
  })),
  ContainerClient: jest.fn(),
}));

process.env.STORAGE_ACCOUNT_NAME = 'stcliquepixtest';

// Import AFTER mocks + env are set.
import { deleteMediaAssets } from '../shared/services/blobService';

beforeEach(() => {
  deletedBlobs.length = 0;
  listedPrefixes.length = 0;
});

describe('deleteMediaAssets', () => {
  it('prefix-deletes the entire video directory (HLS + fallback + poster + original)', async () => {
    await deleteMediaAssets({
      blob_path: 'photos/c1/e1/vid1/original.mp4',
      thumbnail_blob_path: null,
      media_type: 'video',
    });

    expect(listedPrefixes).toEqual(['photos/c1/e1/vid1/']);
    expect(deletedBlobs).toEqual(
      expect.arrayContaining([
        'photos/c1/e1/vid1/original.mp4',
        'photos/c1/e1/vid1/hls/manifest.m3u8',
        'photos/c1/e1/vid1/hls/segment_000.ts',
        'photos/c1/e1/vid1/hls/segment_001.ts',
        'photos/c1/e1/vid1/fallback.mp4',
        'photos/c1/e1/vid1/poster.jpg',
      ]),
    );
    expect(deletedBlobs).toHaveLength(6);
  });

  it('does NOT delete a sibling video whose id is a prefix-superset', async () => {
    await deleteMediaAssets({
      blob_path: 'photos/c1/e1/vid1/original.mp4',
      thumbnail_blob_path: null,
      media_type: 'video',
    });
    expect(deletedBlobs).not.toContain('photos/c1/e1/vid1x/original.mp4');
  });

  it('deletes original + thumbnail for a photo row (no prefix list)', async () => {
    await deleteMediaAssets({
      blob_path: 'photos/c1/e1/p1/original.jpg',
      thumbnail_blob_path: 'photos/c1/e1/p1/thumb.jpg',
      media_type: 'photo',
    });
    expect(listedPrefixes).toEqual([]);
    expect(deletedBlobs).toEqual([
      'photos/c1/e1/p1/original.jpg',
      'photos/c1/e1/p1/thumb.jpg',
    ]);
  });

  it('deletes only original when a photo has no thumbnail', async () => {
    await deleteMediaAssets({
      blob_path: 'photos/c1/e1/p1/original.jpg',
      thumbnail_blob_path: null,
      media_type: 'photo',
    });
    expect(deletedBlobs).toEqual(['photos/c1/e1/p1/original.jpg']);
  });
});
