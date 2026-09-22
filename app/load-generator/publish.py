"""Bursts N messages into the demo topic, then stops -- used to trigger a
KEDA scale-up and, once the burst drains, prove the scale-down back to zero.

Usage:
    python publish.py --count 200 --project my-project --topic keda-demo-work-queue
"""
import argparse
import time

from google.cloud import pubsub_v1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--count", type=int, default=200, help="messages to publish")
    args = parser.parse_args()

    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(args.project, args.topic)

    start = time.time()
    futures = [publisher.publish(topic_path, f"demo-message-{i}".encode()) for i in range(args.count)]
    for f in futures:
        f.result()

    print(f"published {args.count} messages to {topic_path} in {time.time() - start:.1f}s")


if __name__ == "__main__":
    main()
