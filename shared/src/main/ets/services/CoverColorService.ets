export class CoverColorService {
  private static instance: CoverColorService | null = null

  static getInstance(): CoverColorService {
    if (CoverColorService.instance === null) {
      CoverColorService.instance = new CoverColorService()
    }
    return CoverColorService.instance
  }

  cached(_url: string): number {
    return 0
  }

  async resolve(_url: string): Promise<number> {
    return 0
  }
}
