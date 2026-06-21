import { AppStorageV2 } from '@kit.ArkUI'

export const APP_COLOR_FAVORITES_V2_KEY: string = 'v2:appColorFavorites'
export const DEFAULT_APP_COLOR_FAVORITES: string[] = [
  '#F44336',
  '#E91E63',
  '#9C27B0',
  '#673AB7',
  '#3F51B5',
  '#2196F3',
  '#03A9F4',
  '#00BCD4',
  '#009688',
  '#4CAF50',
  '#8BC34A',
  '#CDDC39',
  '#FFEB3B',
  '#FFC107',
  '#FF9800',
  '#FF5722',
  '#795548',
  '#607D8B',
  '#9E9E9E',
]

@ObservedV2
export class AppColorFavoritesState {
  @Trace colors: string[] = DEFAULT_APP_COLOR_FAVORITES
}

export function connectAppColorFavorites(): AppColorFavoritesState {
  return AppStorageV2.connect(
    AppColorFavoritesState,
    APP_COLOR_FAVORITES_V2_KEY,
    () => new AppColorFavoritesState(),
  )!
}
