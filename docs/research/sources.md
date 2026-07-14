# Research Sources

Consolidated source list behind the technical decisions in docs 01–05. Research conducted July 2026;
re-verify version numbers and pricing at implementation time.

## Flutter / Supabase / offline stack
- State management: [Foresight Mobile](https://foresightmobile.com/blog/best-flutter-state-management) · [ASOasis Bloc vs Riverpod 2026](https://asoasis.tech/articles/2026-04-17-2054-flutter-bloc-vs-riverpod-comparison-2026/)
- Offline-first: [Supabase offline-first (Brick)](https://supabase.com/blog/offline-first-flutter-apps) · [Luci Studio DB landscape 2026](https://luci-studio.com/blog/the-flutter-local-database-landscape-in-2026-a-maintenance-first-guide-fe6d267c/) · [Drift offline-first](https://flutterstudio.dev/blog/offline-first-flutter-drift.html)
- Isar status: [isar#1689 "Isar is dead"](https://github.com/isar/isar/issues/1689) · [isar_plus](https://pub.dev/packages/isar_plus)
- PowerSync: [PowerSync + Supabase guide](https://docs.powersync.com/integrations/supabase/guide) · [PowerSync Flutter tutorial](https://powersync.com/blog/flutter-tutorial-building-an-offline-first-chat-app-with-supabase-and-powersync)
- Supabase SDK: [supabase_flutter](https://pub.dev/packages/supabase_flutter) · [Supabase Flutter docs](https://supabase.com/docs/reference/dart/introduction)
- Barcode: [mobile_scanner](https://pub.dev/packages/mobile_scanner) · [openfoodfacts (Dart)](https://pub.dev/packages/openfoodfacts)
- Health/sensors: [health](https://pub.dev/packages/health) · [Flutter Gems Health & Fitness](https://fluttergems.dev/health-fitness/)
- Routing: [go_router](https://pub.dev/packages/go_router) · [Flutter navigation docs](https://docs.flutter.dev/ui/navigation)
- Architecture: [Code with Andrea: project structure](https://codewithandrea.com/articles/flutter-project-structure/) · [Scaling feature-first](https://dev.to/alaminkarno/scaling-flutter-apps-with-feature-first-folder-structures-547f)

## AI layer (LiteLLM / BYOK / vision / cost)
- LiteLLM: [Virtual keys](https://docs.litellm.ai/docs/proxy/virtual_keys) · [BYOK tutorial](https://docs.litellm.ai/docs/tutorials/claude_code_byok) · [BerriAI/litellm](https://github.com/BerriAI/litellm) · [Vision](https://docs.litellm.ai/docs/completion/vision) · [JSON mode](https://docs.litellm.ai/docs/completion/json_mode) · [Streaming](https://docs.litellm.ai/docs/completion/stream) · [structured-output #6998](https://github.com/BerriAI/litellm/issues/6998) · [Budgets & rate limits](https://docs.litellm.ai/docs/proxy/users)
- Mobile security: [Mobile App Security 2026](https://opendoordigital.dev/blog/mobile-app-security-best-practices) · [Quokka State of Mobile App Security 2026](https://www.quokka.io/blog/the-state-of-mobile-app-security-2026-report-findings) · [IBM BYOK](https://www.ibm.com/think/topics/byok)
- Edge Functions: [Architecture](https://supabase.com/docs/guides/functions/architecture) · [Supabase production architecture 2026](https://www.frontendtechlead.com/blog/supabase-production-architecture-2026) · [LiteLLM Supabase logging](https://docs.litellm.ai/docs/observability/supabase_integration)
- Vision cost: [Claude Vision](https://platform.claude.com/docs/en/build-with-claude/vision) · [Images cost 3x in Opus 4.7](https://www.claudecodecamp.com/p/images-cost-3x-more-tokens-in-claude-opus-4-7) · [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing) · [OpenAI pricing](https://developers.openai.com/api/docs/pricing) · [Food tracker w/ GPT-4o](https://dev.to/frosnerd/build-your-own-food-tracker-with-openai-platform-55n8) · [Claude pricing 2026](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration)
- Cost control: [Prompt caching 2026](https://www.digitalapplied.com/blog/prompt-caching-2026-cut-llm-costs-engineering-guide) · [Gateway routing](https://lushbinary.com/blog/llm-gateway-model-routing-cost-optimization-guide/) · [Caching/batching/routing](https://www.gmicloud.ai/en/blog/llm-inference-cost-optimization-caching-batching-routing) · [Claude pricing/caching/batch](https://platform.claude.com/docs/en/about-claude/pricing)

## Indian food database
- Open Food Facts: [API conditions](https://support.openfoodfacts.org/help/en-gb/12-api-data-reuse/94-are-there-conditions-to-use-the-api) · [Terms of use](https://world.openfoodfacts.org/terms-of-use) · [India 10K milestone](https://blog.openfoodfacts.org/en/news/open-food-facts-india-database-reaches-10k-product-milestone) · [Data/exports](https://world.openfoodfacts.org/data) · [Exports repo](https://github.com/openfoodfacts/openfoodfacts-exports)
- IFCT 2017: [PIB release](https://www.pib.gov.in/newsite/PrintRelease.aspx?relid=157486) · [ifct2017 GitHub](https://github.com/ifct2017/ifct2017) · [ifct2017 site](https://ifct2017.github.io/)
- INDB: [INDB page](https://www.anuvaad.org.in/indian-nutrient-databank/) · [PMC paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC11277795/) · [INDB GitHub](https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-)
- USDA: [FDC API guide](https://fdc.nal.usda.gov/api-guide/) · [Data docs](https://fdc.nal.usda.gov/data-documentation/)
- Portions: [DGI 2024 PDF (NIN)](https://nin.res.in/dietaryguidelines/pdfjs/locale/DGI_2024.pdf) · [DGI 2024 (ICMR)](https://main.icmr.nic.in/sites/default/files/upload_documents/DGI_07th_May_2024_fin.pdf) · [NIN](https://www.nin.res.in/)
- Community: [Kaggle 2025](https://www.kaggle.com/datasets/batthulavinay/indian-food-nutrition) · [Kaggle 2026](https://www.kaggle.com/datasets/kashyap077/indian-recipes-ingredients-nutrition-and-cooking)

## Caveats to re-verify at build time
- Exact pub.dev versions for `drift`, `powersync`, `pedometer`, `openfoodfacts`.
- LLM per-token pricing and vision token math (changes frequently).
- `supports_response_schema` behavior per model in LiteLLM.
- Written commercial-use clearance from ICMR-NIN and Anuvaad; legal review of OFF redistribution.
