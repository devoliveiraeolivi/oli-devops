FROM python:3.12-slim
RUN groupadd --gid 1000 app && useradd --uid 1000 --gid app app
USER app
WORKDIR /app
CMD ["python", "-c", "print('hello')"]
