#!/usr/bin/env python3
"""
servicebus-dlq-reprocess.py
============================
LESSON (Issue #8): 4,847 banking transactions in DLQ for 6 days.
No alert. Discovered manually. This script inspects and safely reprocesses.

Usage:
    # Inspect first (no messages removed):
    python servicebus-dlq-reprocess.py --namespace bankcore-servicebus-prod \
        --queue ledger-posting-queue --action inspect

    # Reprocess after deploying the fix:
    python servicebus-dlq-reprocess.py --namespace bankcore-servicebus-prod \
        --queue ledger-posting-queue --action reprocess --batch-size 50
"""

import argparse
import json
import time
import logging
from datetime import datetime, timezone
from collections import Counter

from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.identity import DefaultAzureCredential

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)


def get_client(namespace):
    return ServiceBusClient(
        fully_qualified_namespace=f"{namespace}.servicebus.windows.net",
        credential=DefaultAzureCredential(),
    )


def inspect(client, queue_name, max_peek=500):
    dlq = f"{queue_name}/$DeadLetterQueue"
    total, reasons, oldest, newest = 0, Counter(), None, None

    with client:
        receiver = client.get_queue_receiver(queue_name=dlq, max_wait_time=5)
        with receiver:
            messages = receiver.peek_messages(max_message_count=max_peek)
            for msg in messages:
                total += 1
                reasons[msg.dead_letter_reason or "Unknown"] += 1
                t = msg.enqueued_time_utc
                if t:
                    if not oldest or t < oldest: oldest = t
                    if not newest or t > newest: newest = t

    print(f"\n=== DLQ INSPECTION: {queue_name} ===")
    print(f"Total messages : {total}")
    print(f"Oldest message : {oldest}")
    print(f"Newest message : {newest}")
    print(f"\nError reasons:")
    for reason, count in reasons.most_common():
        print(f"  {count:5d}x  {reason}")


def reprocess(client, queue_name, batch_size=50, delay=2.0, dry_run=False):
    dlq = f"{queue_name}/$DeadLetterQueue"
    done, failed = 0, 0

    log.info(f"{'[DRY RUN] ' if dry_run else ''}Reprocessing DLQ: {dlq} → {queue_name}")

    with client:
        dlq_receiver = client.get_queue_receiver(queue_name=dlq, max_wait_time=5)
        sender = client.get_queue_sender(queue_name=queue_name)

        with dlq_receiver, sender:
            while True:
                msgs = dlq_receiver.receive_messages(max_message_count=batch_size, max_wait_time=5)
                if not msgs:
                    break
                log.info(f"Processing batch of {len(msgs)} messages...")

                if not dry_run:
                    try:
                        batch = sender.create_message_batch()
                        for msg in msgs:
                            new_msg = ServiceBusMessage(
                                body=str(msg),
                                message_id=msg.message_id,
                                application_properties={
                                    **(msg.application_properties or {}),
                                    "reprocessed_from_dlq": "true",
                                    "reprocessed_at": datetime.now(timezone.utc).isoformat(),
                                }
                            )
                            batch.add_message(new_msg)
                        sender.send_messages(batch)
                        for msg in msgs:
                            dlq_receiver.complete_message(msg)
                        done += len(msgs)
                    except Exception as e:
                        log.error(f"Batch failed: {e}")
                        for msg in msgs:
                            dlq_receiver.abandon_message(msg)
                        failed += len(msgs)
                else:
                    log.info(f"[DRY RUN] Would resubmit {len(msgs)} messages")
                    done += len(msgs)

                time.sleep(delay)

    print(f"\n=== REPROCESSING COMPLETE ===")
    print(f"Reprocessed: {done} | Failed: {failed}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--namespace", required=True)
    p.add_argument("--queue", required=True)
    p.add_argument("--action", choices=["inspect", "reprocess"], default="inspect")
    p.add_argument("--batch-size", type=int, default=50)
    p.add_argument("--delay", type=float, default=2.0)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    client = get_client(args.namespace)

    if args.action == "inspect":
        inspect(client, args.queue)
    elif args.action == "reprocess":
        if not args.dry_run:
            confirm = input("Type 'yes' to confirm reprocessing DLQ messages: ")
            if confirm.lower() != "yes":
                print("Aborted.")
                return
        reprocess(client, args.queue, args.batch_size, args.delay, args.dry_run)


if __name__ == "__main__":
    main()
