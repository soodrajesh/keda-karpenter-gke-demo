import os
import time

from google.cloud import pubsub_v1

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
SUBSCRIPTION = os.environ["PUBSUB_SUBSCRIPTION"]
WORK_DURATION_SECONDS = float(os.environ.get("WORK_DURATION_SECONDS", "5"))

subscriber = pubsub_v1.SubscriberClient()
subscription_path = subscriber.subscription_path(PROJECT_ID, SUBSCRIPTION)


def handle_message(message: pubsub_v1.subscriber.message.Message) -> None:
    print(f"received message {message.message_id}, simulating {WORK_DURATION_SECONDS}s of work")
    time.sleep(WORK_DURATION_SECONDS)
    message.ack()


def main() -> None:
    print(f"pulling from {subscription_path}")
    future = subscriber.subscribe(subscription_path, callback=handle_message)
    try:
        future.result()
    except KeyboardInterrupt:
        future.cancel()
        future.result()


if __name__ == "__main__":
    main()
