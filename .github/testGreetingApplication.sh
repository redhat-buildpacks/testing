#!/usr/bin/env bash
CONTAINER_NAME=$1
CONTAINER_IMAGE=$2

# Run container
docker run -d --rm --name $CONTAINER_NAME -p 8081:8080 $CONTAINER_IMAGE

# Wait until app is running
while ! docker logs $CONTAINER_NAME | grep -q "Installed features";
do
    sleep 1
done

# Verify app is running
RESULT=$(curl localhost:8081/hello/greeting/coder)
docker rm -f $CONTAINER_NAME
if [[ "$RESULT" != "hello coder" ]]
then
echo "Application failed to start"
exit 1
fi