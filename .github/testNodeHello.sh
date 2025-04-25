#!/usr/bin/env bash
CONTAINER_NAME=$1
CONTAINER_IMAGE=$2

# Run container
docker run -d --rm --name $CONTAINER_NAME -p 8080:8080 $CONTAINER_IMAGE
if [ $? -ne 0 ]; then
  echo "❌ Failed to start container $CONTAINER_NAME as image do not exist !"
  exit 1
fi

# Wait until app is running
while ! docker logs $CONTAINER_NAME | grep -q "Listening on port 8080";
do
    sleep 1
done

# Verify app is running
RESULT=$(curl -s localhost:8080/api/greeting?name=buildpacker)
docker rm -f $CONTAINER_NAME
if [[ "$RESULT" != "{\"content\":\"Hello, buildpacker\"}" ]]; then
  echo "Application failed to start"
  exit 1
fi