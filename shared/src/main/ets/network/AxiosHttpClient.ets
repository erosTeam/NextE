import axios, { AxiosRequestConfig, AxiosResponse } from '@ohos/axios'

export class AxiosTextResponse {
  statusCode: number = 0
  body: string = ''
  rawHeader: string = ''
}

export class AxiosBinaryResponse {
  statusCode: number = 0
  body: string = ''
  bytes: ArrayBuffer | null = null
  rawHeader: string = ''
}

export class AxiosHttpClient {
  static async requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    const config: AxiosRequestConfig<string> = {
      url: url,
      method: method,
      headers: headers,
      responseType: 'string',
      connectTimeout: connectTimeoutMs,
      readTimeout: readTimeoutMs,
      timeout: readTimeoutMs,
      validateStatus: AxiosHttpClient.acceptStatus,
    }
    if (body.length > 0) {
      config.data = body
    }
    const resp: AxiosResponse<string, string> =
      await axios.request<string, AxiosResponse<string, string>, string>(config)
    const out: AxiosTextResponse = new AxiosTextResponse()
    out.statusCode = resp.status
    out.body = typeof resp.data === 'string' ? resp.data : ''
    out.rawHeader = JSON.stringify(resp.headers)
    return out
  }

  static async requestBinary(
    url: string,
    headers: Record<string, string>,
    maxBytes: number,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosBinaryResponse> {
    const config: AxiosRequestConfig<string> = {
      url: url,
      method: 'GET',
      headers: headers,
      responseType: 'array_buffer',
      maxContentLength: maxBytes,
      connectTimeout: connectTimeoutMs,
      readTimeout: readTimeoutMs,
      timeout: readTimeoutMs,
      validateStatus: AxiosHttpClient.acceptStatus,
    }
    const resp: AxiosResponse<ArrayBuffer, string> =
      await axios.request<ArrayBuffer, AxiosResponse<ArrayBuffer, string>, string>(config)
    const out: AxiosBinaryResponse = new AxiosBinaryResponse()
    out.statusCode = resp.status
    out.rawHeader = JSON.stringify(resp.headers)
    if (resp.data instanceof ArrayBuffer) {
      out.bytes = resp.data
    } else {
      out.body = JSON.stringify(resp.data)
    }
    return out
  }

  private static acceptStatus(status: number): boolean {
    return status >= 100 && status <= 599
  }
}
