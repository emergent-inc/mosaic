import { describe, expect, test } from "bun:test";
import {
  getTestimonialSubtitle,
  getTestimonialTranslation,
  type Testimonial,
} from "../app/[locale]/testimonials";

describe("testimonial translations", () => {
  const nonEnglishTestimonial = {
    key: "minixalpha",
    name: "minixalpha",
    handle: "@minixalpha",
    avatar: "/avatars/minixalpha.jpg",
    text: "Original testimonial",
    lang: "es",
    url: "https://x.com/minixalpha/status/2037496984890986576",
    platform: "x" as const,
  } satisfies Testimonial;

  test("does not translate testimonials already in the reader language", () => {
    const translation = getTestimonialTranslation(
      nonEnglishTestimonial,
      "es",
      () => "English translation"
    );

    expect(translation).toBeNull();
  });

  test("shows English translations for non-English testimonials", () => {
    const translation = getTestimonialTranslation(
      nonEnglishTestimonial,
      "en",
      (key) => {
        expect(key).toBe("minixalpha");
        return "English translation";
      }
    );

    expect(translation).toBe("English translation");
  });

  test("resolves localized testimonial subtitles by key", () => {
    const testimonialWithSubtitleKey = {
      ...nonEnglishTestimonial,
      subtitleKey: "steipete",
    } satisfies Testimonial;

    const subtitle = getTestimonialSubtitle(
      testimonialWithSubtitleKey,
      (key) => {
        expect(key).toBe("steipete");
        return "Localized subtitle";
      }
    );

    expect(subtitle).toBe("Localized subtitle");
  });
});
