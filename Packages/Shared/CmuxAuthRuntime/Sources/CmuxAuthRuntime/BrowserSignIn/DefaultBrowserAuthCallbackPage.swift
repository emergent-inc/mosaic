#if os(macOS)
import Foundation

struct DefaultBrowserAuthCallbackPage {
    let title: String

    func html() -> String {
        let escapedTitle = htmlEscaped(title)
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedTitle)</title>
          <style>
            :root {
              color-scheme: dark;
              --background: #0a0a0a;
              --foreground: #ffffff;
              --border: rgba(255, 255, 255, 0.1);
              --card: #0f0f0f;
            }
            * {
              box-sizing: border-box;
            }
            body {
              align-items: center;
              background: var(--background);
              color: var(--foreground);
              display: flex;
              font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              justify-content: center;
              margin: 0;
              min-height: 100vh;
              padding: 24px;
            }
            main {
              background: var(--card);
              border: 1px solid var(--border);
              border-radius: 24px;
              box-shadow: none;
              max-width: 440px;
              padding: 40px;
              text-align: center;
              width: 100%;
            }
            h1 {
              font-size: 28px;
              font-weight: 650;
              letter-spacing: -0.04em;
              margin: 0;
            }
            @media (max-width: 480px) {
              main {
                border-radius: 18px;
                padding: 32px 24px;
              }
              h1 {
                font-size: 24px;
              }
            }
          </style>
        </head>
        <body>
          <main>
            <h1>\(escapedTitle)</h1>
          </main>
          <script>window.close()</script>
        </body>
        </html>
        """
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
#endif
