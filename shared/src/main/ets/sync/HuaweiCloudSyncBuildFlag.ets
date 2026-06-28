// Local development defaults to exposing Huawei Cloud sync. Public release builds without AGC/HGC cloud
// setup can run `NEXTE_HUAWEI_CLOUD_SYNC=0 scripts/build_hvigor_signed.sh` to temporarily disable it.
export const HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = true
