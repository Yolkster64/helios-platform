FROM python:3.12-slim
WORKDIR /app
COPY . .
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health')"
CMD ["python", "app.py"]

