import Foundation
import Markdown

/// HTML is generated from the syntax tree. Raw HTML and remote images are never emitted.
public enum MarkdownRenderer {
    public static func html(_ source: String) -> String {
        let document = Document(parsing: source)
        return """
        <!doctype html><html lang="fr"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'">
        <style>
        :root{color-scheme:light dark}*{box-sizing:border-box}
        body{margin:0;padding:28px 36px 60px;font:15px/1.75 -apple-system,BlinkMacSystemFont,sans-serif;color:#2b2b30;background:#fff;overflow-wrap:anywhere}
        article{max-width:820px;margin:auto}h1{font-size:28px;line-height:1.3;margin:0 0 24px;letter-spacing:-.6px}
        h2{font-size:20px;margin:30px 0 10px}h3{font-size:17px}p{margin:0 0 16px}
        a{color:#4259a8}blockquote{margin:20px 0;padding-left:18px;border-left:3px solid #d5d9e4;color:#72727a}
        code{font:13px/1.65 ui-monospace,Menlo,monospace;background:#f3f2ee;padding:2px 5px;border-radius:4px}
        pre{background:#f3f2ee;padding:18px;border-radius:8px;overflow-x:auto}pre code{padding:0;background:none}
        hr{border:0;border-top:1px solid #e2e0da;margin:28px 0}li{margin:4px 0}
        table{border-collapse:collapse;width:100%}td,th{border:1px solid #ddd;padding:8px;text-align:left}
        @media(prefers-color-scheme:dark){body{background:#202122;color:#e6e6e8}code,pre{background:#2b2c2e}a{color:#a5b5ff}blockquote{color:#a5a5af;border-color:#50535c}}
        </style></head><body><article>\(render(document))</article></body></html>
        """
    }

    private static func render(_ node: any Markup) -> String {
        let content = { node.children.map { render($0) }.joined() }
        switch node {
        case let text as Markdown.Text: return escape(text.string)
        case let heading as Heading: return "<h\(heading.level)>\(content())</h\(heading.level)>"
        case is Paragraph: return "<p>\(content())</p>"
        case is Strong: return "<strong>\(content())</strong>"
        case is Emphasis: return "<em>\(content())</em>"
        case is Strikethrough: return "<del>\(content())</del>"
        case let code as InlineCode: return "<code>\(escape(code.code))</code>"
        case let code as CodeBlock: return "<pre><code>\(escape(code.code))</code></pre>"
        case let list as OrderedList: return "<ol start=\"\(list.startIndex)\">\(content())</ol>"
        case is UnorderedList: return "<ul>\(content())</ul>"
        case is ListItem: return "<li>\(content())</li>"
        case is BlockQuote: return "<blockquote>\(content())</blockquote>"
        case is ThematicBreak: return "<hr>"
        case is LineBreak: return "<br>"
        case is SoftBreak: return "\n"
        case let link as Link:
            guard let destination = link.destination, let url = URL(string: destination),
                  ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return content() }
            return "<a href=\"\(escape(destination))\">\(content())</a>"
        case let image as Markdown.Image: return "<span>\(escape(image.plainText))</span>"
        case let html as HTMLBlock: return "<pre>\(escape(html.rawHTML))</pre>"
        case let html as InlineHTML: return escape(html.rawHTML)
        case is Table: return "<table>\(content())</table>"
        case is Table.Head:
            return "<thead><tr>" + node.children.map { cell in
                "<th>" + cell.children.map { render($0) }.joined() + "</th>"
            }.joined() + "</tr></thead>"
        case is Table.Body: return "<tbody>\(content())</tbody>"
        case is Table.Row: return "<tr>\(content())</tr>"
        case is Table.Cell: return "<td>\(content())</td>"
        default: return content()
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
