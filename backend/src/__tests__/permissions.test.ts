import { canDeleteMedia } from '../shared/utils/permissions';

const UPLOADER = 'uploader-uuid';
const ORGANIZER = 'organizer-uuid';
const RANDOM = 'random-uuid';

describe('canDeleteMedia', () => {
  it('returns "uploader" when caller uploaded the media', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: UPLOADER,
        eventCreatedByUserId: ORGANIZER,
        authUserId: UPLOADER,
      }),
    ).toBe('uploader');
  });

  it('returns "organizer" when caller is event creator and not the uploader', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: UPLOADER,
        eventCreatedByUserId: ORGANIZER,
        authUserId: ORGANIZER,
      }),
    ).toBe('organizer');
  });

  it('returns "uploader" when caller is both uploader and organizer (uploader precedence)', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: UPLOADER,
        eventCreatedByUserId: UPLOADER,
        authUserId: UPLOADER,
      }),
    ).toBe('uploader');
  });

  it('returns null for a random clique member who is neither uploader nor organizer', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: UPLOADER,
        eventCreatedByUserId: ORGANIZER,
        authUserId: RANDOM,
      }),
    ).toBeNull();
  });

  it('returns null when both ID columns are null (deleted accounts)', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: null,
        eventCreatedByUserId: null,
        authUserId: RANDOM,
      }),
    ).toBeNull();
  });

  it('returns null when authUserId is empty (defense-in-depth)', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: UPLOADER,
        eventCreatedByUserId: ORGANIZER,
        authUserId: '',
      }),
    ).toBeNull();
  });

  it('still resolves "organizer" when uploader account was deleted (uploadedByUserId null)', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: null,
        eventCreatedByUserId: ORGANIZER,
        authUserId: ORGANIZER,
      }),
    ).toBe('organizer');
  });

  it('still resolves "uploader" when organizer account was deleted (eventCreatedByUserId null)', () => {
    expect(
      canDeleteMedia({
        uploadedByUserId: UPLOADER,
        eventCreatedByUserId: null,
        authUserId: UPLOADER,
      }),
    ).toBe('uploader');
  });
});
