# Build the documentation site

The site uses MkDocs Material. Existing repository guides are inserted during the build by `tool/docs_hook.py`; edit the canonical Markdown rather than copying it into `website/`.

## Install and build

Use Python 3.11 or later. From the repository root:

```sh
python3 -m venv .dart_tool/docs-venv
.dart_tool/docs-venv/bin/python -m pip install -r tool/docs-requirements.txt
.dart_tool/docs-venv/bin/mkdocs build --strict
```

The generated site is in `.dart_tool/docs-site/`. To preview it:

```sh
.dart_tool/docs-venv/bin/mkdocs serve --dev-addr 127.0.0.1:8000
```

Search uses a local index generated with the site. The interface supports dark and light themes, keyboard navigation, code copying, and mobile navigation. No analytics service is configured. Font stacks use locally available system fonts.

## Edit a page

Canonical guides live in `docs/`, `CONTRIBUTING.md`, `AGENTS.md`, and the Serverpod example README. Site-specific tutorials and assets live in `website/`. Navigation and theme configuration live in `mkdocs.yml`.

Add new canonical guides to the navigation when they become reader-facing. The build fails on missing pages and broken internal links. Run the documentation checks before opening a pull request:

```sh
.dart_tool/docs-venv/bin/python -m unittest discover -s tool -p 'test_docs_site.py'
.dart_tool/docs-venv/bin/mkdocs build --strict
```

## GitHub Pages deployment

`.github/workflows/pages.yml` builds documentation for pull requests and deploys a successful build on `main` or manual dispatch. It uses GitHub's Pages artifact and deployment actions.

The repository owner must select **GitHub Actions** as the Pages source in repository settings before the first deployment. The intended project URL is `https://seifalmotaz.github.io/agent-weave/`. Preparing this workflow does not by itself mean the site is deployed.

Relative asset and navigation URLs work under the repository subpath. The workflow does not publish Dart packages or invoke paid provider tests.

## Generator maintenance

MkDocs Material 9.8.0 receives security fixes through May 5, 2027. Its maintainers
recommend Zensical as the successor. Review that migration before the support
window ends. The guides remain ordinary Markdown; the integration-specific
code is the virtual-file hook and the MkDocs configuration. Do not disable the
upstream notice to hide this maintenance requirement.
