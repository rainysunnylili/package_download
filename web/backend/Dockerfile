# Backend Dockerfile
FROM python:3.13-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install nvm and multiple Node.js versions
ENV NVM_DIR=/root/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install 18 && \
    nvm install 20 && \
    nvm install 22 && \
    nvm alias default 20

# Set working directory
WORKDIR /app

# Copy backend code
COPY web/backend/app /app/app
COPY web/backend/requirements.txt /app/
COPY web/scripts /app/scripts

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create task directory
RUN mkdir -p /tmp/pkg-download-tasks

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
