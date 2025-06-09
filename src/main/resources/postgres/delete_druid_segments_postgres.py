#!/usr/bin/env python3
import psycopg2
import argparse
import time
from datetime import datetime


def connect_to_postgres(host, port, dbname, user, password):
    """Connect to PostgreSQL database and return connection object."""
    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            dbname=dbname,
            user=user,
            password=password
        )
        print(f"Successfully connected to PostgreSQL database: {dbname}")
        return conn
    except Exception as e:
        print(f"Error connecting to PostgreSQL database: {e}")
        raise


def delete_in_batches(conn, datasource, batch_size, dry_run=False, sleep_time=0):
    """Delete rows in batches from druid_segments table."""
    cursor = conn.cursor()

    total_deleted = 0
    start_time = time.time()
    ShouldDelete = True
    try:
        while ShouldDelete:
            # Get batch of IDs to delete
            select_query = f"""
            SELECT id FROM druid_segments 
            WHERE used = 'f'
            LIMIT {batch_size}
            """

            cursor.execute(select_query, (datasource,))
            rows = cursor.fetchall()

            if not rows:
                print(f"No more rows to delete. Total deleted: {total_deleted}")
                break

            # Extract IDs from result
            ids_to_delete = [row[0] for row in rows]
            batch_count = len(ids_to_delete)

            # Print info about this batch
            print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - Found {batch_count} rows to delete in this batch")

            if not dry_run:
                # Delete rows by ID
                delete_query = f"""
                DELETE FROM druid_segments 
                WHERE id = ANY(%s)
                """

                cursor.execute(delete_query, (ids_to_delete,))
                conn.commit()

                total_deleted += batch_count
                print(f"Deleted {batch_count} rows. Total deleted so far: {total_deleted}")
            else:
                print(f"[DRY RUN] Would delete {batch_count} rows. Total would be: {total_deleted + batch_count}")
                total_deleted += batch_count

            ShouldDelete = True
            # Sleep between batches if requested
            if sleep_time > 0:
                print(f"Sleeping for {sleep_time} seconds...")
                time.sleep(sleep_time)

    except Exception as e:
        print(f"Error during batch deletion: {e}")
        conn.rollback()
        raise
    finally:
        cursor.close()

    end_time = time.time()
    duration = end_time - start_time
    print(f"Operation completed in {duration:.2f} seconds")
    print(f"Total rows deleted: {total_deleted}")

    return total_deleted


def main():
    parser = argparse.ArgumentParser(description='Delete rows in batches from druid_segments table')

    # Connection parameters
    parser.add_argument('--host', default='localhost', help='Database host')
    parser.add_argument('--port', type=int, default=5432, help='Database port')
    parser.add_argument('--dbname', required=True, help='Database name')
    parser.add_argument('--user', required=True, help='Database user')
    parser.add_argument('--password', required=True, help='Database password')

    # Operation parameters
    parser.add_argument('--datasource', default='event-ac-50db6658-8bde-4ac0-9b2c-f596d5ca1748',
                        help='Datasource value to filter by')
    parser.add_argument('--batch-size', type=int, default=1000,
                        help='Number of rows to delete in each batch')
    parser.add_argument('--sleep', type=int, default=0,
                        help='Sleep time between batches in seconds')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run without actually deleting data')

    args = parser.parse_args()

    # Connect to database
    conn = connect_to_postgres(
        args.host, args.port, args.dbname, args.user, args.password
    )

    try:
        print(f"Starting batch deletion process for datasource: {args.datasource}")
        print(f"Batch size: {args.batch_size}, Sleep time: {args.sleep}s, Dry run: {args.dry_run}")

        # Perform batch deletion
        delete_in_batches(
            conn,
            args.datasource,
            args.batch_size,
            False,
            args.sleep
        )

    finally:
        conn.close()
        print("Database connection closed")


if __name__ == "__main__":
    main()
