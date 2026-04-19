/**
 * Downloads a blob from a cross-origin SAS URL and triggers a browser download.
 * Uses fetch + URL.createObjectURL because Safari ignores the `download`
 * attribute on cross-origin anchors.
 */
export async function downloadBlob(url: string, filename: string): Promise<void> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed: ${response.status}`);
  const blob = await response.blob();
  const objectUrl = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = objectUrl;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
}
