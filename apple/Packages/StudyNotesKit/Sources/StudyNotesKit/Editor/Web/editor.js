import { Editor, Extension, Node, mergeAttributes } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"
import TaskList from "@tiptap/extension-task-list"
import TaskItem from "@tiptap/extension-task-item"
import { TableKit } from "@tiptap/extension-table"
import DragHandle from "@tiptap/extension-drag-handle"
import Placeholder from "@tiptap/extension-placeholder"
import { Markdown } from "tiptap-markdown"
import { defaultMarkdownSerializer } from "prosemirror-markdown"
import { Plugin, PluginKey } from "@tiptap/pm/state"
import { Decoration, DecorationSet } from "@tiptap/pm/view"

const bridge = window.webkit?.messageHandlers?.markdownEditor
const titleInput = document.getElementById("title")
const sourceText = document.getElementById("source")
const editorHost = document.getElementById("editor")
const sourceToggle = document.getElementById("source-toggle")
const outline = document.getElementById("outline")
const outlineList = document.getElementById("outline-list")
const findPanel = document.getElementById("find-panel")
const findQuery = document.getElementById("find-query")
const findCount = document.getElementById("find-count")
const slashMenu = document.getElementById("slash-menu")
const statusBanner = document.getElementById("status-banner")

let compatibilityBlocks = []
let compatibilityByToken = new Map()
let isSourceMode = false
let ignoreUpdates = false
let publishTimer
let sourceTimer
let slashPosition = null

function post(message) {
  bridge?.postMessage(message)
}

function showStatus(message) {
  statusBanner.textContent = message
  statusBanner.hidden = !message
  if (message) {
    window.clearTimeout(showStatus.timer)
    showStatus.timer = window.setTimeout(() => {
      statusBanner.hidden = true
    }, 5000)
  }
}

let closeImagePreview = () => {}

function openImagePreview(sourceImage) {
  closeImagePreview()

  const source = sourceImage.currentSrc || sourceImage.src
  if (!source) {
    return
  }
  const previousFocus = document.activeElement

  const overlay = document.createElement("div")
  overlay.className = "sn-image-preview"
  overlay.setAttribute("role", "dialog")
  overlay.setAttribute("aria-label", "图片预览")

  const previewImage = document.createElement("img")
  previewImage.className = "sn-image-preview-image"
  previewImage.src = source
  previewImage.alt = sourceImage.alt || ""
  previewImage.draggable = false

  const controls = document.createElement("div")
  controls.className = "sn-image-preview-controls"

  const zoomLabel = document.createElement("span")
  zoomLabel.textContent = "100%"
  zoomLabel.style.minWidth = "38px"
  zoomLabel.style.textAlign = "center"

  const closeButton = document.createElement("button")
  closeButton.type = "button"
  closeButton.className = "sn-image-preview-close"
  closeButton.textContent = "×"
  closeButton.title = "关闭预览"
  closeButton.setAttribute("aria-label", "关闭图片预览")

  controls.append(zoomLabel, closeButton)
  overlay.append(previewImage, controls)

  let scale = 1
  let translateX = 0
  let translateY = 0
  let drag = null

  const applyTransform = () => {
    previewImage.style.transform =
      `translate3d(${translateX}px, ${translateY}px, 0) scale(${scale})`
    zoomLabel.textContent = `${Math.round(scale * 100)}%`
  }

  const zoomAt = event => {
    const nextScale = Math.max(
      0.25,
      Math.min(8, scale * Math.exp(-event.deltaY * 0.0015))
    )
    if (Math.abs(nextScale - scale) < 0.0001) {
      return
    }
    const rect = overlay.getBoundingClientRect()
    const originX = event.clientX - rect.left - rect.width / 2
    const originY = event.clientY - rect.top - rect.height / 2
    const ratio = nextScale / scale
    translateX = originX - (originX - translateX) * ratio
    translateY = originY - (originY - translateY) * ratio
    scale = nextScale
    applyTransform()
  }

  overlay.addEventListener("wheel", event => {
    event.preventDefault()
    event.stopPropagation()
    zoomAt(event)
  }, { passive: false })

  previewImage.addEventListener("pointerdown", event => {
    event.preventDefault()
    previewImage.setPointerCapture(event.pointerId)
    drag = {
      pointerID: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      originX: translateX,
      originY: translateY
    }
    previewImage.style.cursor = "grabbing"
  })

  previewImage.addEventListener("pointermove", event => {
    if (!drag || drag.pointerID !== event.pointerId) {
      return
    }
    translateX = drag.originX + event.clientX - drag.startX
    translateY = drag.originY + event.clientY - drag.startY
    applyTransform()
  })

  const endDrag = event => {
    if (!drag || drag.pointerID !== event.pointerId) {
      return
    }
    drag = null
    previewImage.style.cursor = "grab"
  }
  previewImage.addEventListener("pointerup", endDrag)
  previewImage.addEventListener("pointercancel", endDrag)

  const handleKeyDown = event => {
    if (event.key === "Escape") {
      event.preventDefault()
      closeImagePreview()
    }
  }

  closeImagePreview = () => {
    document.removeEventListener("keydown", handleKeyDown)
    overlay.remove()
    previousFocus?.focus?.()
    closeImagePreview = () => {}
  }

  closeButton.addEventListener("click", closeImagePreview)
  overlay.addEventListener("click", event => {
    if (event.target === overlay) {
      closeImagePreview()
    }
  })
  previewImage.addEventListener("dblclick", event => {
    event.preventDefault()
    event.stopPropagation()
    closeImagePreview()
  })
  document.addEventListener("keydown", handleKeyDown)
  document.body.append(overlay)
  applyTransform()
  closeButton.focus()
}

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

function tokenFor(index) {
  return `studynotes-compat-${index}`
}

function preprocessMarkdown(markdown, blocks) {
  compatibilityBlocks = blocks ?? []
  compatibilityByToken = new Map()
  const lines = markdown.replaceAll("\r\n", "\n").replaceAll("\r", "\n").split("\n")
  const replacements = compatibilityBlocks
    .map((block, index) => ({ block, index }))
    .sort((left, right) => right.block.startLine - left.block.startLine)

  replacements.forEach(({ block, index }) => {
    const token = tokenFor(index)
    compatibilityByToken.set(token, block)
    const start = Math.max(0, block.startLine - 1)
    const end = Math.min(lines.length - 1, block.endLine - 1)
    const placeholder = [
      "",
      `<div data-studynotes-compat="${token}"></div>`,
      ""
    ]
    lines.splice(start, end - start + 1, ...placeholder)
  })
  return lines.join("\n")
}

const CompatibilityBlock = Node.create({
  name: "compatibilityBlock",
  group: "block",
  atom: true,
  selectable: true,
  draggable: false,
  isolating: true,

  addAttributes() {
    return {
      token: { default: "" },
      kind: { default: "unknown" },
      source: { default: "" }
    }
  },

  parseHTML() {
    return [{
      tag: "div[data-studynotes-compat]",
      priority: 100,
      getAttrs: element => {
        const token = element.getAttribute("data-studynotes-compat") ?? ""
        const block = compatibilityByToken.get(token)
        return {
          token,
          kind: block?.kind ?? "unknown",
          source: block?.source ?? element.textContent ?? ""
        }
      }
    }]
  },

  renderHTML({ node, HTMLAttributes }) {
    return [
      "div",
      mergeAttributes(HTMLAttributes, {
        class: "compat-block",
        "data-studynotes-compat": node.attrs.token,
        contenteditable: "false"
      }),
      ["div", { class: "compat-label" }, "兼容内容 · 源文本可编辑"],
      ["pre", {}, node.attrs.source]
    ]
  },

  addStorage() {
    return {
      markdown: {
        serialize(state, node) {
          state.write(node.attrs.source)
          if (node.isBlock) {
            state.closeBlock(node)
          }
        }
      }
    }
  }
})

const MarkdownBlockImage = Image.extend({
  addStorage() {
    return {
      markdown: {
        serialize(state, node, parent, index) {
          defaultMarkdownSerializer.nodes.image(
            state,
            node,
            parent,
            index
          )
          if (node.isBlock) {
            state.closeBlock(node)
          }
        },
        parse: {}
      }
    }
  }
})

const SearchPluginKey = new PluginKey("studynotes-search")

const SearchExtension = Extension.create({
  name: "studynotesSearch",

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: SearchPluginKey,
        state: {
          init: () => ({ query: "", index: 0, matches: [] }),
          apply(transaction, previous) {
            const meta = transaction.getMeta(SearchPluginKey)
            if (meta) {
              const query = meta.query ?? previous.query
              const matches = findMatches(transaction.doc, query)
              let index = previous.index
              if (meta.query !== undefined) {
                index = 0
              }
              if (meta.direction) {
                index = matches.length
                  ? (index + meta.direction + matches.length) % matches.length
                  : 0
              }
              return { query, index, matches }
            }
            if (transaction.docChanged) {
              return {
                ...previous,
                matches: findMatches(transaction.doc, previous.query)
              }
            }
            return previous
          }
        },
        props: {
          decorations(state) {
            const search = SearchPluginKey.getState(state)
            if (!search?.query) {
              return DecorationSet.empty
            }
            const decorations = search.matches.map((match, index) =>
              Decoration.inline(match.from, match.to, {
                class: index === search.index
                  ? "search-hit search-current"
                  : "search-hit"
              })
            )
            return DecorationSet.create(state.doc, decorations)
          }
        }
      })
    ]
  }
})

const editor = new Editor({
  element: editorHost,
  extensions: [
    StarterKit.configure({
      link: false
    }),
    Link.configure({
      openOnClick: false,
      autolink: true,
      defaultProtocol: "https",
      HTMLAttributes: {
        rel: "noopener noreferrer",
        target: "_blank"
      }
    }),
    MarkdownBlockImage.configure({
      allowBase64: false,
      inline: false,
      HTMLAttributes: {
        class: "editor-image"
      }
    }),
    TaskList,
    TaskItem.configure({ nested: true }),
    TableKit.configure({
      table: { resizable: false }
    }),
    Placeholder.configure({
      placeholder: ({ node }) =>
        node.type.name === "heading" ? "标题" : "输入正文，或输入 / 插入内容"
    }),
    CompatibilityBlock,
    SearchExtension,
    DragHandle.configure({
      render: () => {
        const handle = document.createElement("div")
        handle.className = "drag-handle"
        handle.title = "拖动此块"
        return handle
      },
      nested: true
    }),
    Markdown.configure({
      html: true,
      tightLists: true,
      bulletListMarker: "-",
      linkify: false,
      breaks: false,
      transformPastedText: true,
      transformCopiedText: true
    })
  ],
  content: "",
  editorProps: {
    attributes: {
      spellcheck: "true",
      "aria-label": "笔记正文"
    }
  },
  onUpdate: () => {
    if (!ignoreUpdates) {
      updateToolbar()
      refreshOutline()
      schedulePublish()
    }
  },
  onSelectionUpdate: updateToolbar,
  onTransaction: updateToolbar
})

editor.view.dom.addEventListener("keydown", event => {
  const commandKey = event.metaKey || event.ctrlKey
  if (commandKey && event.key.toLowerCase() === "s") {
    event.preventDefault()
    post({ type: "saveRequested" })
    return
  }
  if (commandKey && event.key.toLowerCase() === "f") {
    event.preventDefault()
    toggleFind(true)
    return
  }
  if (event.key === "/" && !event.shiftKey && !isSourceMode) {
    event.preventDefault()
    slashPosition = editor.state.selection.from
    openSlashMenu()
  }
  if (event.key === "Escape") {
    closeSlashMenu()
    toggleFind(false)
  }
})

editor.view.dom.addEventListener("click", event => {
  const image = event.target.closest?.("img")
  if (!image || !editor.view.dom.contains(image)) {
    return
  }
  event.preventDefault()
  event.stopPropagation()
  openImagePreview(image)
}, true)

titleInput.addEventListener("input", () => {
  if (ignoreUpdates) {
    return
  }
  syncTitleHeading(titleInput.value)
  schedulePublish()
})

document.getElementById("toolbar").addEventListener("click", event => {
  const button = event.target.closest("button[data-command]")
  if (!button) {
    return
  }
  runCommand(button.dataset.command)
})

document.getElementById("attach-image").addEventListener("click", () => {
  post({ type: "attachRequested", attachmentKind: "image" })
})

document.getElementById("attach-file").addEventListener("click", () => {
  post({ type: "attachRequested", attachmentKind: "file" })
})

document.getElementById("outline-toggle").addEventListener("click", () => {
  outline.hidden = !outline.hidden
  refreshOutline()
})

document.getElementById("outline-close").addEventListener("click", () => {
  outline.hidden = true
})

document.getElementById("find-toggle").addEventListener("click", () => {
  toggleFind(findPanel.hidden)
})

document.getElementById("find-close").addEventListener("click", () => {
  toggleFind(false)
})

document.getElementById("find-next").addEventListener("click", () => {
  runFind(findQuery.value, 1)
})

document.getElementById("find-previous").addEventListener("click", () => {
  runFind(findQuery.value, -1)
})

findQuery.addEventListener("input", () => {
  runFind(findQuery.value, 0)
})

sourceToggle.addEventListener("click", () => {
  setSourceMode(!isSourceMode)
})

sourceText.addEventListener("input", () => {
  window.clearTimeout(sourceTimer)
  sourceTimer = window.setTimeout(() => {
    post({ type: "sourceChanged", markdown: sourceText.value })
  }, 100)
})

slashMenu.addEventListener("click", event => {
  const button = event.target.closest("button[data-block]")
  if (!button) {
    return
  }
  applyBlock(button.dataset.block)
})

document.addEventListener("pointerdown", event => {
  if (!slashMenu.hidden
      && !slashMenu.contains(event.target)
      && !event.target.closest("[data-command]")) {
    closeSlashMenu()
  }
})

function loadDocument(message) {
  ignoreUpdates = true
  compatibilityBlocks = message.compatibilityBlocks ?? []
  titleInput.value = message.title ?? ""
  const prepared = preprocessMarkdown(
    message.markdown ?? "",
    compatibilityBlocks
  )
  editor.commands.setContent(prepared, { emitUpdate: false })
  ignoreUpdates = false
  updateToolbar()
  refreshOutline()
  if (isSourceMode) {
    sourceText.value = message.markdown ?? ""
  }
}

function serializeMarkdown() {
  return editor.storage.markdown.getMarkdown().trimEnd()
}

function schedulePublish() {
  window.clearTimeout(publishTimer)
  publishTimer = window.setTimeout(() => {
    post({ type: "markdownChanged", markdown: serializeMarkdown() })
    post({ type: "titleChanged", title: titleInput.value.trim() })
  }, 120)
}

function syncTitleHeading(title) {
  const normalized = title.trim()
  if (!normalized) {
    return
  }
  let headingPosition = null
  editor.state.doc.descendants((node, position) => {
    if (headingPosition === null
        && node.type.name === "heading"
        && node.attrs.level === 1) {
      headingPosition = position
      return false
    }
    return true
  })

  ignoreUpdates = true
  if (headingPosition !== null) {
    const heading = editor.state.doc.nodeAt(headingPosition)
    if (heading) {
      const from = headingPosition + 1
      const to = headingPosition + heading.nodeSize - 1
      editor.commands.command(({ tr }) => {
        tr.replaceWith(from, to, normalized ? editor.schema.text(normalized) : [])
        return true
      })
    }
  } else {
    editor.commands.insertContentAt(0, {
      type: "heading",
      attrs: { level: 1 },
      content: [{ type: "text", text: normalized }]
    })
  }
  ignoreUpdates = false
  refreshOutline()
}

function setSourceMode(enabled) {
  if (enabled === isSourceMode) {
    return
  }
  isSourceMode = enabled
  sourceToggle.classList.toggle("active", enabled)
  sourceText.hidden = !enabled
  editorHost.hidden = enabled
  if (enabled) {
    sourceText.value = serializeMarkdown()
    sourceText.focus()
    post({ type: "sourceModeChanged", sourceMode: true })
  } else {
    post({ type: "sourceChanged", markdown: sourceText.value })
    loadDocument({
      markdown: sourceText.value,
      title: titleInput.value,
      compatibilityBlocks
    })
    post({ type: "sourceModeChanged", sourceMode: false })
    editor.commands.focus("start")
  }
}

function runCommand(command) {
  const chain = editor.chain().focus()
  switch (command) {
  case "undo":
    chain.undo().run()
    break
  case "redo":
    chain.redo().run()
    break
  case "heading1":
    chain.toggleHeading({ level: 1 }).run()
    break
  case "heading2":
    chain.toggleHeading({ level: 2 }).run()
    break
  case "bold":
    chain.toggleBold().run()
    break
  case "italic":
    chain.toggleItalic().run()
    break
  case "strike":
    chain.toggleStrike().run()
    break
  case "code":
    chain.toggleCode().run()
    break
  case "link":
    editLink(chain)
    break
  case "quote":
    chain.toggleBlockquote().run()
    break
  case "bulletList":
    chain.toggleBulletList().run()
    break
  case "orderedList":
    chain.toggleOrderedList().run()
    break
  case "taskList":
    chain.toggleTaskList().run()
    break
  case "codeBlock":
    chain.toggleCodeBlock().run()
    break
  case "table":
    chain.insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run()
    break
  default:
    break
  }
  updateToolbar()
}

function editLink(chain) {
  if (editor.isActive("link")) {
    chain.unsetLink().run()
    return
  }
  const href = window.prompt("链接地址", "https://")
  if (href?.trim()) {
    chain.extendMarkRange("link").setLink({ href: href.trim() }).run()
  }
}

function updateToolbar() {
  const active = {
    bold: editor.isActive("bold"),
    italic: editor.isActive("italic"),
    strike: editor.isActive("strike"),
    code: editor.isActive("code"),
    link: editor.isActive("link"),
    heading1: editor.isActive("heading", { level: 1 }),
    heading2: editor.isActive("heading", { level: 2 }),
    quote: editor.isActive("blockquote"),
    bulletList: editor.isActive("bulletList"),
    orderedList: editor.isActive("orderedList"),
    taskList: editor.isActive("taskList"),
    codeBlock: editor.isActive("codeBlock")
  }
  Object.entries(active).forEach(([command, enabled]) => {
    document.querySelector(`[data-command="${command}"]`)
      ?.classList.toggle("active", enabled)
  })
}

function getHeadings() {
  const headings = []
  editor.state.doc.descendants((node, position) => {
    if (node.type.name === "heading") {
      headings.push({
        level: node.attrs.level,
        text: node.textContent || "无标题",
        position
      })
    }
    return true
  })
  return headings
}

function refreshOutline() {
  outlineList.replaceChildren()
  const headings = getHeadings()
  if (!headings.length) {
    const empty = document.createElement("div")
    empty.className = "panel-heading"
    empty.textContent = "当前文档没有标题"
    outlineList.append(empty)
    return
  }
  headings.forEach(heading => {
    const button = document.createElement("button")
    button.textContent = heading.text
    button.style.paddingLeft = `${8 + (heading.level - 1) * 14}px`
    button.addEventListener("click", () => {
      editor.commands.setTextSelection(heading.position + 1)
      editor.commands.focus()
      editor.view.nodeDOM(heading.position)?.scrollIntoView({
        block: "start",
        behavior: "smooth"
      })
      if (window.matchMedia("(max-width: 680px)").matches) {
        outline.hidden = true
      }
    })
    outlineList.append(button)
  })
}

function toggleFind(show) {
  findPanel.hidden = !show
  if (show) {
    findQuery.focus()
    findQuery.select()
  } else {
    runFind("", 0)
  }
}

function runFind(query, direction) {
  const transaction = editor.state.tr.setMeta(SearchPluginKey, {
    query,
    direction
  })
  editor.view.dispatch(transaction)
  const state = SearchPluginKey.getState(editor.state)
  if (!state) {
    return
  }
  findCount.textContent = `${state.matches.length ? state.index + 1 : 0}/${state.matches.length}`
  const match = state.matches[state.index]
  if (match) {
    const dom = editor.view.domAtPos(match.from)
    dom.node.parentElement?.scrollIntoView({
      block: "center",
      behavior: "smooth"
    })
  }
}

function findMatches(doc, query) {
  const normalized = query.trim().toLocaleLowerCase()
  if (!normalized) {
    return []
  }
  const matches = []
  doc.descendants((node, position) => {
    if (!node.isText || !node.text) {
      return true
    }
    const text = node.text.toLocaleLowerCase()
    let offset = text.indexOf(normalized)
    while (offset >= 0) {
      matches.push({
        from: position + offset,
        to: position + offset + normalized.length
      })
      offset = text.indexOf(normalized, offset + normalized.length)
    }
    return true
  })
  return matches
}

const slashItems = [
  ["heading1", "H1", "一级标题", "#"],
  ["heading2", "H2", "二级标题", "##"],
  ["quote", "❝", "引用", ">"],
  ["bulletList", "•", "无序列表", "-"],
  ["orderedList", "1.", "有序列表", "1."],
  ["taskList", "☑", "任务列表", "[ ]"],
  ["codeBlock", "{ }", "代码块", "```"],
  ["table", "▦", "表格", ""],
  ["horizontalRule", "—", "分割线", "---"],
  ["image", "Img", "图片占位", "![...]"],
  ["file", "File", "附件占位", "[...]"]
]

function openSlashMenu() {
  slashMenu.replaceChildren()
  slashItems.forEach(([id, icon, label, hint]) => {
    const button = document.createElement("button")
    button.dataset.block = id
    button.innerHTML = [
      `<span class="slash-icon">${escapeHTML(icon)}</span>`,
      `<span>${escapeHTML(label)}</span>`,
      `<span class="slash-hint">${escapeHTML(hint)}</span>`
    ].join("")
    slashMenu.append(button)
  })
  slashMenu.hidden = false
  const position = editor.view.coordsAtPos(slashPosition ?? editor.state.selection.from)
  slashMenu.style.left = `${Math.max(12, Math.min(position.left, window.innerWidth - 260))}px`
  slashMenu.style.top = `${Math.min(position.bottom + 6, window.innerHeight - 330)}px`
}

function closeSlashMenu() {
  slashMenu.hidden = true
  slashPosition = null
}

function applyBlock(block) {
  if (slashPosition !== null) {
    editor.commands.setTextSelection(slashPosition)
  }
  closeSlashMenu()
  if (block === "horizontalRule") {
    editor.chain().focus().setHorizontalRule().run()
  } else if (block === "image") {
    post({ type: "attachRequested", attachmentKind: "image" })
    return
  } else if (block === "file") {
    post({ type: "attachRequested", attachmentKind: "file" })
    return
  } else {
    runCommand(block)
  }
}

window.StudyNotesEditor = {
  receive(message) {
    switch (message.type) {
    case "loadDocument":
      loadDocument(message)
      break
    case "titleChanged":
      ignoreUpdates = true
      titleInput.value = message.title ?? ""
      ignoreUpdates = false
      break
    case "sourceChanged":
      sourceText.value = message.markdown ?? ""
      break
    case "command":
      if (message.command === "save") {
        post({ type: "saveRequested" })
      } else if (message.command === "undo") {
        editor.commands.undo()
      } else if (message.command === "redo") {
        editor.commands.redo()
      } else if (message.command === "focusTitle") {
        titleInput.focus()
      } else if (message.command === "enterSourceMode") {
        setSourceMode(true)
      } else if (message.command === "exitSourceMode") {
        setSourceMode(false)
      }
      break
    case "failed":
      showStatus(message.reason ?? "编辑器发生错误")
      break
    default:
      break
    }
  },

  setTheme(theme) {
    document.documentElement.dataset.theme = theme === "dark" ? "dark" : "light"
  },

  setEditable(editable) {
    editor.setEditable(Boolean(editable))
  },

  insertMediaReference(reference, kind = "image", label = "") {
    if (!reference.startsWith("media://qiniu/")) {
      showStatus("媒体必须使用 media://qiniu/<objectKey> 稳定引用。")
      return false
    }
    const text = kind === "image"
      ? `![${label || "图片"}](${reference})`
      : `[${label || "附件"}](${reference})`
    editor.chain().focus().insertContent(text).run()
    return true
  }
}

post({ type: "ready" })
