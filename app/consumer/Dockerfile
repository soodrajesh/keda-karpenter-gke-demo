FROM python:3.12-slim

# Without this, Python block-buffers stdout when it isn't a TTY (always
# true in a container), so `kubectl logs` shows nothing until the buffer
# fills or the process exits.
ENV PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

USER 65532:65532
ENTRYPOINT ["python", "main.py"]
