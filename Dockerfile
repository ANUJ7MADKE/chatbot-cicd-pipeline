# Multi-stage build for minimal image attack surface
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim

# AWS Lambda Web Adapter: lets this same image run unchanged on AWS Lambda.
# Outside Lambda the extension is inactive and uvicorn runs as usual.
# Vendored (see vendor/lambda-adapter/README.md) and checksum-verified.
COPY --chmod=755 vendor/lambda-adapter/lambda-adapter /opt/extensions/lambda-adapter
RUN echo "f4c9748d551878ddd4e612457bb23b869e0a47a53d14e66ed6cab1fd1f797699  /opt/extensions/lambda-adapter" \
    | sha256sum -c -
ENV AWS_LWA_PORT=8000

WORKDIR /app
COPY --from=builder /install /usr/local
COPY ./app ./app

# Run as non-root user for security best practices
RUN useradd -m botuser && chown -R botuser /app
USER botuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
