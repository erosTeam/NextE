ARG BASE_IMAGE=nexte/manga-translator-ui:v1.9.9
FROM ${BASE_IMAGE}

COPY manga_translator/server/request_extraction.py /app/manga_translator/server/request_extraction.py
COPY manga_translator/server/routes/translation.py /app/manga_translator/server/routes/translation.py
COPY manga_translator/manga_translator.py /app/manga_translator/manga_translator.py

LABEL org.opencontainers.image.title="NextE manga-translator-ui compatibility sidecar"
LABEL org.opencontainers.image.version="v1.9.9-nexte2"
LABEL org.opencontainers.image.source="https://github.com/hgmzhn/manga-translator-ui"
LABEL org.opencontainers.image.licenses="GPL-3.0"
