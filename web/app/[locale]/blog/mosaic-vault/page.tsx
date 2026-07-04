import { useTranslations } from "next-intl";
import { getTranslations } from "next-intl/server";
import { buildAlternates } from "../../../../i18n/seo";
import { BlogSchema } from "../blog-schema";
import { Link } from "../../../../i18n/navigation";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "blog.mosaicVault" });
  const rawKeywords = t.raw("metaKeywords");
  const keywords = Array.isArray(rawKeywords)
    ? rawKeywords.filter((keyword): keyword is string => typeof keyword === "string")
    : [];
  return {
    title: t("metaTitle"),
    description: t("metaDescription"),
    keywords,
    openGraph: {
      title: t("metaTitle"),
      description: t("metaDescription"),
      type: "article",
      publishedTime: "2026-05-22T00:00:00Z",
    },
    twitter: {
      card: "summary_large_image",
      title: t("metaTitle"),
      description: t("metaDescription"),
    },
    alternates: buildAlternates(locale, "/blog/mosaic-vault"),
  };
}

export default function MosaicVaultPage() {
  const t = useTranslations("blog.posts.mosaicVault");
  const tc = useTranslations("common");

  return (
    <>
      <BlogSchema postKey="mosaicVault" path="/blog/mosaic-vault" datePublished="2026-05-22T00:00:00Z" />
      <div className="mb-8">
        <Link
          href="/blog"
          className="text-sm text-muted hover:text-foreground transition-colors"
        >
          &larr; {tc("backToBlog")}
        </Link>
      </div>

      <h1>{t("title")}</h1>
      <time dateTime="2026-05-22" className="text-sm text-muted">
        {t("date")}
      </time>

      <video
        src="/blog/mosaic-vault.mp4"
        width={1280}
        height={902}
        autoPlay
        loop
        muted
        playsInline
        className="my-6 rounded-lg w-full h-auto"
      />

      <p>{t("p1")}</p>
      <p>{t("p2")}</p>
      <p>{t("p3")}</p>
      <p>{t("p4")}</p>
    </>
  );
}
