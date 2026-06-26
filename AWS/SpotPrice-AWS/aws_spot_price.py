#!/usr/bin/env python3
"""
aws_spot_price.py
-----------------

A parallelized AWS Spot Instance price fetcher.

This tool:
  - Discovers all AWS regions that support Spot Instances
  - Fetches the latest Spot price per Availability Zone
  - Deduplicates by keeping the *lowest* price per AZ
  - Sorts globally and prints the cheapest 20 entries

Key features:
  - ThreadPoolExecutor for fast multi‑region querying
  - Uses Spot Price History API (24h window)
  - Clean tabular output for quick comparison

Usage:
  python aws_spot_price.py --instance-type t3.micro
"""

import boto3
import argparse
from tabulate import tabulate
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta


# ---------------------------------------------------------------------------
# Region Discovery
# ---------------------------------------------------------------------------

def get_spot_instance_regions():
    """
    Discover AWS regions that support Spot Instances.

    Strategy:
      1. Query the global region list from us-east-1.
      2. For each region, attempt a minimal Spot Price History call.
      3. If the call succeeds → Spot is supported.
      4. If it fails → region is skipped silently.

    Returns:
      List[str]: Regions where Spot Instances are available.
    """
    ec2_client = boto3.client("ec2", region_name="us-east-1")
    regions = [r["RegionName"] for r in ec2_client.describe_regions()["Regions"]]

    supported_regions = []

    for region in regions:
        try:
            ec2 = boto3.client("ec2", region_name=region)

            # Probe request — if Spot is unsupported, AWS throws an error.
            ec2.describe_spot_price_history(
                InstanceTypes=["t3.micro"],
                MaxResults=1
            )

            supported_regions.append(region)

        except Exception:
            # Region does not support Spot — ignore.
            pass

    return supported_regions


# ---------------------------------------------------------------------------
# Spot Price Fetching
# ---------------------------------------------------------------------------

def fetch_latest_spot_prices(region, instance_type):
    """
    Fetch the latest Spot prices for a given instance type in a region.

    AWS returns multiple entries per AZ with different timestamps.
    We:
      - Query up to 24 hours of history.
      - Group by Availability Zone.
      - Keep the *lowest* price per AZ.
      - Return rows formatted for tabulation.

    Args:
      region (str): AWS region name.
      instance_type (str): EC2 instance type.

    Returns:
      List[List]: Rows in format [AZ, InstanceType, Price, Timestamp].
    """
    try:
        ec2 = boto3.client("ec2", region_name=region)

        response = ec2.describe_spot_price_history(
            InstanceTypes=[instance_type],
            ProductDescriptions=["Linux/UNIX"],
            MaxResults=50,
            StartTime=datetime.utcnow() - timedelta(days=1)
        )

        latest_prices = {}

        for entry in response["SpotPriceHistory"]:
            az = entry["AvailabilityZone"]
            price = float(entry["SpotPrice"])
            timestamp = entry["Timestamp"]

            # Keep the lowest price per AZ.
            if az not in latest_prices or price < latest_prices[az][2]:
                latest_prices[az] = [
                    az,
                    entry["InstanceType"],
                    price,
                    timestamp
                ]

        return list(latest_prices.values())

    except Exception as e:
        print(f"Error fetching spot prices for {region}: {e}")
        return []


# ---------------------------------------------------------------------------
# Main Execution Flow
# ---------------------------------------------------------------------------

def main():
    """
    Main entry point:
      - Parse CLI args.
      - Discover Spot-enabled regions.
      - Fetch prices in parallel.
      - Flatten, sort, and print the cheapest 20 entries.
    """
    parser = argparse.ArgumentParser(
        description="Fetch latest AWS Spot Instance prices."
    )
    parser.add_argument(
        "--instance-type",
        required=True,
        help="AWS instance type (e.g., t3.micro, m5.large)"
    )
    args = parser.parse_args()

    # Discover all regions supporting Spot.
    regions = get_spot_instance_regions()

    # Parallel region scanning for speed.
    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(
            executor.map(
                lambda r: fetch_latest_spot_prices(r, args.instance_type),
                regions
            )
        )

    # Flatten nested lists and sort by price.
    spot_prices = sorted(
        [item for sublist in results for item in sublist],
        key=lambda x: x[2]
    )[:20]

    headers = ["Availability Zone", "Instance", "Price ($)", "Timestamp"]

    print("\nLatest Spot Price Per Unique Availability Zone:")
    print(tabulate(spot_prices, headers=headers, tablefmt="plain"))


if __name__ == "__main__":
    main()
