FROM eclipse-temurin:21-jre-jammy
ARG OMIXER_VERSION=1.1
ENV OMIXER_JAR=/opt/omixer/omixer-rpm.jar
WORKDIR /opt/omixer

# Download the release artifact (adjust filename if the asset name differs)
# Tip: check the exact asset name on the Releases page.
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/* && \
    curl -L -o "$OMIXER_JAR" \
      "https://github.com/raeslab/omixer-rpm/releases/download/${OMIXER_VERSION}/omixer-rpm-${OMIXER_VERSION}.jar"

ENTRYPOINT ["java","-jar","/opt/omixer/omixer-rpm.jar"]
CMD ["--help"]

ENV PATH="/opt/conda/bin:$PATH"