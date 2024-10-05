FROM ghcr.io/gleam-lang/gleam:v1.5.1-erlang-alpine

COPY . /build

RUN cd /build \
    && gleam export erlang-shipment \
    && mv build/erlang-shipment /app \
    && rm -rf /build

ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD [ "run" ]
