# NOTE: pin to a digest after first build — docker inspect python:3.13-slim
# then replace the tag with python:3.13-slim@sha256:<digest> (README claims
# digest-pinned bases).
FROM python:3.13-slim

COPY oob_logger.py /oob_logger.py
RUN mkdir -p /data
ENV OOB_LOG=/data/hits.log OOB_BIND_PORT=8080
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["python", "/oob_logger.py"]
