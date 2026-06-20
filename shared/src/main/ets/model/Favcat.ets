/**
 * One favorites category (favcat) slot 0-9, parsed from the favorites.php selector bar
 * (EhFavcatListParser). Mirrors eros_fe's Favcat. `favId` is the 0-9 slot, `favTitle` the
 * user's (possibly localized) name, `totNum` the gallery count in that slot.
 */
export class Favcat {
  favId: string = ''
  favTitle: string = ''
  totNum: number = 0
  isPlaceholder: boolean = false

  constructor(favId: string = '', favTitle: string = '', totNum: number = 0, isPlaceholder: boolean = false) {
    this.favId = favId
    this.favTitle = favTitle
    this.totNum = totNum
    this.isPlaceholder = isPlaceholder
  }
}
