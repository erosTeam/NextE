export const EH_IMAGE_PRIORITY_HIGH: number = 0
export const EH_IMAGE_PRIORITY_MEDIUM: number = 1
export const EH_IMAGE_PRIORITY_LOW: number = 2

// Gallery covers are small, latency-sensitive list assets. Keep these separate from reader-image
// timeouts so a stalled thumbnail cannot occupy a global ImageKnife network slot for a full minute.
export const EH_THUMBNAIL_CONNECT_TIMEOUT_MS: number = 3000
export const EH_THUMBNAIL_READ_TIMEOUT_MS: number = 5000

export const EH_IMAGE_DOWNSAMPLING_NONE: number = 0
export const EH_IMAGE_DOWNSAMPLING_DEFAULT: number = 1
export const EH_IMAGE_DOWNSAMPLING_FIT_CENTER_MEMORY: number = 2
export const EH_IMAGE_DOWNSAMPLING_FIT_CENTER_QUALITY: number = 3
export const EH_IMAGE_DOWNSAMPLING_CENTER_INSIDE_MEMORY: number = 4
export const EH_IMAGE_DOWNSAMPLING_CENTER_INSIDE_QUALITY: number = 5
export const EH_IMAGE_DOWNSAMPLING_AT_LEAST: number = 6
export const EH_IMAGE_DOWNSAMPLING_AT_MOST: number = 7
export const EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_FILL: number = 8
export const EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FIT: number = 9
export const EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FILL: number = 10
