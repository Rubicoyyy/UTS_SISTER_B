FROM python:3.11-slim
WORKDIR /app

# create non-root user early
RUN adduser --disabled-password --gecos '' appuser

# install dependencies as root
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# copy application files
COPY src/ ./src/
COPY scripts/ ./scripts/

# create data dir and ensure ownership for non-root user
RUN mkdir -p /app/data /app/scripts && chown -R appuser:appuser /app

# switch to non-root user
USER appuser

EXPOSE 8080
CMD ["python", "-m", "src.main"]
