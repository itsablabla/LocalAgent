FROM swift:5.9-focal AS builder
WORKDIR /build
COPY Package.swift .
COPY Sources/ Sources/
RUN swift build -c release --product LocalAgentServer

FROM swift:5.9-focal
RUN apt-get update && apt-get install -y \
    libcurl4 \
    curl \
    tzdata \
    ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/.build/release/LocalAgentServer .
ENTRYPOINT ["./LocalAgentServer"]
