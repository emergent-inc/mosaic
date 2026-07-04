import { useTranslations } from "next-intl";
import { getTranslations } from "next-intl/server";
import { buildAlternates } from "../../../../i18n/seo";
import { DocsSchema } from "../docs-schema";
import { CodeBlock } from "../../components/code-block";
import { DocsHeading } from "../../components/docs-heading";

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "docs.browserAutomation" });
  return {
    title: t("metaTitle"),
    description: t("metaDescription"),
    alternates: buildAlternates(locale, "/docs/browser-automation"),
  };
}

export default function BrowserAutomationPage() {
  const t = useTranslations("docs.browserAutomation");

  return (
    <>
      <DocsSchema namespace="docs.browserAutomation" path="/docs/browser-automation" />
      <DocsHeading level={1} id="title">{t("title")}</DocsHeading>
      <p>{t("intro")}</p>

      <DocsHeading level={2} id="command-index">{t("commandIndex")}</DocsHeading>
      <table>
        <thead>
          <tr>
            <th>{t("categoryHeader")}</th>
            <th>{t("subcommandsHeader")}</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>{t("navAndTargeting")}</td>
            <td>
              <code>identify</code>, <code>open</code>, <code>open-split</code>,{" "}
              <code>navigate</code>, <code>back</code>, <code>forward</code>,{" "}
              <code>reload</code>, <code>url</code>, <code>focus-webview</code>,{" "}
              <code>is-webview-focused</code>, <code>zoom</code>,{" "}
              <code>focus-mode</code>, <code>react-grab</code>, <code>devtools</code>
            </td>
          </tr>
          <tr>
            <td>{t("waiting")}</td>
            <td>
              <code>wait</code>
            </td>
          </tr>
          <tr>
            <td>{t("domInteraction")}</td>
            <td>
              <code>click</code>, <code>dblclick</code>, <code>hover</code>,{" "}
              <code>focus</code>, <code>check</code>, <code>uncheck</code>,{" "}
              <code>scroll-into-view</code>, <code>type</code>, <code>fill</code>,{" "}
              <code>press</code>, <code>keydown</code>, <code>keyup</code>,{" "}
              <code>select</code>, <code>scroll</code>
            </td>
          </tr>
          <tr>
            <td>{t("inspection")}</td>
            <td>
              <code>snapshot</code>, <code>screenshot</code>, <code>get</code>,{" "}
              <code>is</code>, <code>find</code>, <code>highlight</code>
            </td>
          </tr>
          <tr>
            <td>{t("jsAndInjection")}</td>
            <td>
              <code>eval</code>, <code>addinitscript</code>, <code>addscript</code>,{" "}
              <code>addstyle</code>
            </td>
          </tr>
          <tr>
            <td>{t("framesDialogsDownloads")}</td>
            <td>
              <code>frame</code>, <code>dialog</code>, <code>download</code>
            </td>
          </tr>
          <tr>
            <td>{t("stateAndSession")}</td>
            <td>
              <code>cookies</code>, <code>storage</code>, <code>state</code>,{" "}
              <code>history</code>
            </td>
          </tr>
          <tr>
            <td>{t("tabsAndLogs")}</td>
            <td>
              <code>tab</code>, <code>console</code>, <code>errors</code>
            </td>
          </tr>
        </tbody>
      </table>

      <DocsHeading level={2} id="targeting-surface">{t("targetingSurface")}</DocsHeading>
      <p>{t("targetingDesc")}</p>
      <CodeBlock lang="bash">{`# Open a new browser split
mosaic browser open https://example.com

# Discover focused IDs and browser metadata
mosaic browser identify
mosaic browser identify --surface surface:2

# Positional vs flag targeting are equivalent
mosaic browser surface:2 url
mosaic browser --surface surface:2 url`}</CodeBlock>

      <DocsHeading level={2} id="navigation">{t("navigation")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser open https://example.com
mosaic browser open-split https://news.ycombinator.com

mosaic browser surface:2 navigate https://example.org/docs --snapshot-after
mosaic browser surface:2 back
mosaic browser surface:2 forward
mosaic browser surface:2 reload --snapshot-after
mosaic browser surface:2 url

mosaic browser surface:2 focus-webview
mosaic browser surface:2 is-webview-focused

mosaic browser react-grab toggle
mosaic browser devtools toggle
mosaic browser devtools console
mosaic browser focus-mode toggle
mosaic browser zoom in
mosaic browser zoom reset
mosaic browser history clear --force`}</CodeBlock>

      <DocsHeading level={2} id="waiting-section">{t("waitingSection")}</DocsHeading>
      <p>{t("waitingDesc")}</p>
      <CodeBlock lang="bash">{`mosaic browser surface:2 wait --load-state complete --timeout-ms 15000
mosaic browser surface:2 wait --selector "#checkout" --timeout-ms 10000
mosaic browser surface:2 wait --text "Order confirmed"
mosaic browser surface:2 wait --url-contains "/dashboard"
mosaic browser surface:2 wait --function "window.__appReady === true"`}</CodeBlock>

      <DocsHeading level={2} id="dom-section">{t("domSection")}</DocsHeading>
      <p>{t("domDesc")}</p>
      <CodeBlock lang="bash">{`mosaic browser surface:2 click "button[type='submit']" --snapshot-after
mosaic browser surface:2 dblclick ".item-row"
mosaic browser surface:2 hover "#menu"
mosaic browser surface:2 focus "#email"
mosaic browser surface:2 check "#terms"
mosaic browser surface:2 uncheck "#newsletter"
mosaic browser surface:2 scroll-into-view "#pricing"

mosaic browser surface:2 type "#search" "mosaic"
mosaic browser surface:2 fill "#email" --text "ops@example.com"
mosaic browser surface:2 fill "#email" --text ""
mosaic browser surface:2 press Enter
mosaic browser surface:2 keydown Shift
mosaic browser surface:2 keyup Shift
mosaic browser surface:2 select "#region" "us-east"
mosaic browser surface:2 scroll --dy 800 --snapshot-after
mosaic browser surface:2 scroll --selector "#log-view" --dx 0 --dy 400`}</CodeBlock>

      <DocsHeading level={2} id="inspection-section">{t("inspectionSection")}</DocsHeading>
      <p>{t("inspectionDesc")}</p>
      <CodeBlock lang="bash">{`mosaic browser surface:2 snapshot --interactive --compact
mosaic browser surface:2 snapshot --selector "main" --max-depth 5
mosaic browser surface:2 screenshot --out /tmp/mosaic-page.png

mosaic browser surface:2 get title
mosaic browser surface:2 get url
mosaic browser surface:2 get text "h1"
mosaic browser surface:2 get html "main"
mosaic browser surface:2 get value "#email"
mosaic browser surface:2 get attr "a.primary" --attr href
mosaic browser surface:2 get count ".row"
mosaic browser surface:2 get box "#checkout"
mosaic browser surface:2 get styles "#total" --property color

mosaic browser surface:2 is visible "#checkout"
mosaic browser surface:2 is enabled "button[type='submit']"
mosaic browser surface:2 is checked "#terms"

mosaic browser surface:2 find role button --name "Continue"
mosaic browser surface:2 find text "Order confirmed"
mosaic browser surface:2 find label "Email"
mosaic browser surface:2 find placeholder "Search"
mosaic browser surface:2 find alt "Product image"
mosaic browser surface:2 find title "Open settings"
mosaic browser surface:2 find testid "save-btn"
mosaic browser surface:2 find first ".row"
mosaic browser surface:2 find last ".row"
mosaic browser surface:2 find nth 2 ".row"

mosaic browser surface:2 highlight "#checkout"`}</CodeBlock>

      <DocsHeading level={2} id="js-section">{t("jsSection")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 eval "document.title"
mosaic browser surface:2 eval --script "window.location.href"

mosaic browser surface:2 addinitscript "window.__mosaicReady = true;"
mosaic browser surface:2 addscript "document.querySelector('#name')?.focus()"
mosaic browser surface:2 addstyle "#debug-banner { display: none !important; }"`}</CodeBlock>

      <DocsHeading level={2} id="state-section">{t("stateSection")}</DocsHeading>
      <p>{t("stateDesc")}</p>
      <CodeBlock lang="bash">{`mosaic browser surface:2 cookies get
mosaic browser surface:2 cookies get --name session_id
mosaic browser surface:2 cookies set session_id abc123 --domain example.com --path /
mosaic browser surface:2 cookies clear --name session_id
mosaic browser surface:2 cookies clear --all

mosaic browser surface:2 storage local set theme dark
mosaic browser surface:2 storage local get theme
mosaic browser surface:2 storage local clear
mosaic browser surface:2 storage session set flow onboarding
mosaic browser surface:2 storage session get flow

mosaic browser surface:2 state save /tmp/mosaic-browser-state.json
mosaic browser surface:2 state load /tmp/mosaic-browser-state.json`}</CodeBlock>

      <DocsHeading level={2} id="tabs-section">{t("tabsSection")}</DocsHeading>
      <p>{t("tabsDesc")}</p>
      <CodeBlock lang="bash">{`mosaic browser surface:2 tab list
mosaic browser surface:2 tab new https://example.com/pricing

# Switch by index or by target surface
mosaic browser surface:2 tab switch 1
mosaic browser surface:2 tab switch surface:7

# Close current tab or a specific target
mosaic browser surface:2 tab close
mosaic browser surface:2 tab close surface:7`}</CodeBlock>

      <DocsHeading level={2} id="console-section">{t("consoleSection")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 console list
mosaic browser surface:2 console clear

mosaic browser surface:2 errors list
mosaic browser surface:2 errors clear`}</CodeBlock>

      <DocsHeading level={2} id="dialogs-section">{t("dialogsSection")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 dialog accept
mosaic browser surface:2 dialog accept "Confirmed by automation"
mosaic browser surface:2 dialog dismiss`}</CodeBlock>

      <DocsHeading level={2} id="frames-section">{t("framesSection")}</DocsHeading>
      <CodeBlock lang="bash">{`# Enter an iframe context
mosaic browser surface:2 frame "iframe[name='checkout']"
mosaic browser surface:2 click "#pay-now"

# Return to the top-level document
mosaic browser surface:2 frame main`}</CodeBlock>

      <DocsHeading level={2} id="downloads-section">{t("downloadsSection")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 click "a#download-report"
mosaic browser surface:2 download --path /tmp/report.csv --timeout-ms 30000`}</CodeBlock>

      <DocsHeading level={2} id="common-patterns">{t("commonPatterns")}</DocsHeading>

      <DocsHeading level={3} id="pattern-navigate">{t("patternNavigate")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser open https://example.com/login
mosaic browser surface:2 wait --load-state complete --timeout-ms 15000
mosaic browser surface:2 snapshot --interactive --compact
mosaic browser surface:2 get title`}</CodeBlock>

      <DocsHeading level={3} id="pattern-form">{t("patternForm")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 fill "#email" --text "ops@example.com"
mosaic browser surface:2 fill "#password" --text "$PASSWORD"
mosaic browser surface:2 click "button[type='submit']" --snapshot-after
mosaic browser surface:2 wait --text "Welcome"
mosaic browser surface:2 is visible "#dashboard"`}</CodeBlock>

      <DocsHeading level={3} id="pattern-debug">{t("patternDebug")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 console list
mosaic browser surface:2 errors list
mosaic browser surface:2 screenshot --out /tmp/mosaic-failure.png
mosaic browser surface:2 snapshot --interactive --compact`}</CodeBlock>

      <DocsHeading level={3} id="pattern-session">{t("patternSession")}</DocsHeading>
      <CodeBlock lang="bash">{`mosaic browser surface:2 state save /tmp/session.json
# ...later...
mosaic browser surface:2 state load /tmp/session.json
mosaic browser surface:2 reload`}</CodeBlock>
    </>
  );
}
