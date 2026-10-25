# 离线依赖

阅读器直接加载本地资源，不依赖 CDN。源文件保留第三方许可证与原有声明，不手工改动。

| 资源 | 固定版本 | 包内来源 | 许可证 |
|---|---|---|---|
| Markdown 复制转换 | Turndown 7.2.2 | `turndown` npm 包的 `dist/turndown.js` | [MIT](turndown-LICENSE) |
| 表格与列表扩展 | turndown-plugin-gfm 1.0.2 | npm 包的 `dist/turndown-plugin-gfm.js` | [MIT](turndown-plugin-gfm-LICENSE) |
| Markdown 解析 | 见 [开发依赖](../../../../../package.json) | `marked` npm 包，由打包工具派生浏览器资源 | [MIT](marked-LICENSE) |
| 中文强调 | 见 [开发依赖](../../../../../package.json) | `marked-cjk-friendly` npm 包，由打包工具派生浏览器资源 | [MIT](marked-cjk-friendly-LICENSE) |

解析器与中文强调资源由 [打包工具](../../../../../Tools/build_reader_vendor.mjs) 生成：`node Tools/build_reader_vendor.mjs`；CI 使用 `--check` 核对派生文件，不手工编辑。

复制事件接口参考 [MDN：copy 事件](https://developer.mozilla.org/en-US/docs/Web/API/Element/copy_event)。第三方库转换普通内容，公式源文本处理由 [selection-copy.js](../selection-copy.js) 维护。
