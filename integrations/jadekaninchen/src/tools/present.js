// 工具结果的呈现辅助：DSH 的 ContentBlock 与 OneBot 的消息段形状不同，别混用。

export const textBlock = (text) => [{ type: 'text', text: String(text) }]

export const oneBotText = (text) => [{ type: 'text', data: { text: String(text) } }]
