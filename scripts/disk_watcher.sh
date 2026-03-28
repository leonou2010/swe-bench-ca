#!/bin/bash
# Watches disk space. When < 15GB free, prunes Docker build cache and unused images.
while true; do
    FREE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    if [ "$FREE_GB" -lt 15 ]; then
        echo "$(date): Low disk (${FREE_GB}GB free). Cleaning..."
        docker builder prune -f 2>/dev/null
        # Remove images not used by running containers
        RUNNING=$(docker ps --format "{{.Image}}" 2>/dev/null)
        for IMG in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "jefzda/sweap"); do
            if ! echo "$RUNNING" | grep -q "$IMG"; then
                docker rmi "$IMG" 2>/dev/null && echo "  Removed: $IMG"
            fi
        done
        FREE_AFTER=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
        echo "$(date): Now ${FREE_AFTER}GB free"
    fi
    sleep 120
done
