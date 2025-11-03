import type { SharePayload } from './NitroShareIntent.nitro';

export const ShareIntentUtils = {
  isTextShare: (payload: SharePayload): boolean => {
    return payload.type === 'text' && !!payload.text;
  },

  isFileShare: (payload: SharePayload): boolean => {
    return (
      (payload.type === 'file' || payload.type === 'multiple') &&
      !!payload.files &&
      payload.files.length > 0
    );
  },

  isMultipleFileShare: (payload: SharePayload): boolean => {
    return (
      payload.type === 'multiple' && !!payload.files && payload.files.length > 1
    );
  },

  getSubject: (payload: SharePayload): string | undefined => {
    return payload.extras?.subject;
  },

  getAdditionalText: (payload: SharePayload): string | undefined => {
    return payload.extras?.text;
  },

  getFileExtension: (fileUri: string): string | undefined => {
    const match = fileUri.match(/\.([^./?#]+)(?:[?#]|$)/);
    return match ? match[1]?.toLowerCase() : undefined;
  },

  isImageFile: (fileUri: string): boolean => {
    const ext = ShareIntentUtils.getFileExtension(fileUri);
    return ext
      ? ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].includes(ext)
      : false;
  },

  isVideoFile: (fileUri: string): boolean => {
    const ext = ShareIntentUtils.getFileExtension(fileUri);
    return ext
      ? ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv'].includes(ext)
      : false;
  },

  formatForDisplay: (payload: SharePayload): string => {
    switch (payload.type) {
      case 'text':
        return `Text: ${payload.text}`;
      case 'file':
        return `File: ${payload.files?.[0] || 'Unknown'}`;
      case 'multiple':
        return `Files: ${payload.files?.length || 0} items`;
      default:
        return 'Unknown share type';
    }
  },
};
