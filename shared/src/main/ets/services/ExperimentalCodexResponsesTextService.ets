import { common } from '@kit.AbilityKit'
import { CodexOAuthTokenSet } from '../model/ComicTranslationProvider'
import { AxiosHttpClient, AxiosTextResponse } from '../network/AxiosHttpClient'
import { ExperimentalCodexOAuthService } from './ExperimentalCodexOAuthService'
import { ResponsesTextProtocol } from './ResponsesTextProtocol'

const CODEX_RESPONSES_TEXT_URL: string = 'https://chatgpt.com/backend-api/codex/responses'
const CODEX_RESPONSES_TEXT_ORIGINATOR: string = 'codex_cli_rs'
const CODEX_RESPONSES_TEXT_USER_AGENT: string = 'codex_cli_rs/0.0.0 (NextE experimental)'
const CODEX_RESPONSES_TEXT_CONNECT_TIMEOUT_MS: number = 12000
const CODEX_RESPONSES_TEXT_READ_TIMEOUT_MS: number = 60000
const CODEX_RESPONSES_TEXT_MAX_BODY_CHARS: number = 8 * 1024 * 1024

interface ResponsesTextInput {
  type: string
  text: string
}

class ResponsesTextInputMessage {
  role: string = 'user'
  content: ResponsesTextInput[] = []
}

class CodexResponsesTextReasoning {
}

class CodexResponsesTextRequestBody {
  model: string = ''
  instructions: string = ''
  input: ResponsesTextInputMessage[] = []
  tool_choice: string = 'auto'
  parallel_tool_calls: boolean = false
  reasoning: CodexResponsesTextReasoning | null = null
  store: boolean = false
  stream: boolean = true
  include: string[] = []
}

export class CodexResponsesTextRequestBuilder {
  static build(model: string, instructions: string, input: string): string {
    const message: ResponsesTextInputMessage = new ResponsesTextInputMessage()
    message.content = [{ type: 'input_text', text: input }]
    const body: CodexResponsesTextRequestBody = new CodexResponsesTextRequestBody()
    body.model = model
    body.instructions = instructions
    body.input = [message]
    return JSON.stringify(body)
  }
}

export interface CodexResponsesTextHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse>
}

export class DefaultCodexResponsesTextHttpTransport implements CodexResponsesTextHttpTransport {
  requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    connectTimeoutMs: number,
    readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    return AxiosHttpClient.requestText(
      url,
      method,
      headers,
      body,
      connectTimeoutMs,
      readTimeoutMs,
      CODEX_RESPONSES_TEXT_MAX_BODY_CHARS,
    )
  }
}

/** Executes a text-only Responses request through one stored experimental Codex OAuth source. */
export class ExperimentalCodexResponsesTextService {
  static async generate(
    context: common.UIAbilityContext,
    sourceProfileId: string,
    model: string,
    instructions: string,
    input: string,
    transport: CodexResponsesTextHttpTransport = new DefaultCodexResponsesTextHttpTransport(),
  ): Promise<string> {
    if (sourceProfileId.length === 0 || model.trim().length === 0) {
      throw new Error('Codex text source is not configured')
    }
    if (instructions.trim().length === 0 || input.trim().length === 0) {
      throw new Error('Codex text request is empty')
    }
    let tokens: CodexOAuthTokenSet = await ExperimentalCodexOAuthService.usableSourceTokens(
      context,
      sourceProfileId,
    )
    let response: AxiosTextResponse = await ExperimentalCodexResponsesTextService.request(
      tokens,
      model,
      instructions,
      input,
      transport,
    )
    if (response.statusCode === 401) {
      tokens = await ExperimentalCodexOAuthService.usableSourceTokens(
        context,
        sourceProfileId,
        true,
      )
      response = await ExperimentalCodexResponsesTextService.request(
        tokens,
        model,
        instructions,
        input,
        transport,
      )
    }
    if (response.statusCode !== 200) {
      throw new Error('Codex text request failed (HTTP ' + response.statusCode + ')')
    }
    return ResponsesTextProtocol.extract(response.body, true)
  }

  private static request(
    tokens: CodexOAuthTokenSet,
    model: string,
    instructions: string,
    input: string,
    transport: CodexResponsesTextHttpTransport,
  ): Promise<AxiosTextResponse> {
    const headers: Record<string, string> = {
      'User-Agent': CODEX_RESPONSES_TEXT_USER_AGENT,
      'Accept': 'text/event-stream',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + tokens.accessToken,
      'originator': CODEX_RESPONSES_TEXT_ORIGINATOR,
    }
    if (tokens.accountId.length > 0) {
      headers['ChatGPT-Account-ID'] = tokens.accountId
    }
    return transport.requestText(
      CODEX_RESPONSES_TEXT_URL,
      'POST',
      headers,
      CodexResponsesTextRequestBuilder.build(model, instructions, input),
      CODEX_RESPONSES_TEXT_CONNECT_TIMEOUT_MS,
      CODEX_RESPONSES_TEXT_READ_TIMEOUT_MS,
    )
  }
}
