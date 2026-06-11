import pandas as pd
import subprocess
import argparse

def run_row(row, start, end):
    min_lat = int(90 - (row["y2"] / 3600) * 180)
    max_lat = int(90 - (row["y1"] / 3600) * 180)

    min_lat -= 5
    max_lat += 5

    mrom, img = row["closest_slice"].split('/')
    mrom = mrom.lower()
    img = img.rsplit('.', 1)[0]

    subprocess.run(["./process_one_image.sh", mrom, img, str(min_lat), str(max_lat), str(start), str(end)])


def main():
    parser = argparse.ArgumentParser(description="Process subset of rows by iloc range")
    parser.add_argument("--start", type=int, default=0, help="Start iloc (inclusive)")
    parser.add_argument("--end", type=int, default=None, help="End iloc (exclusive)")
    args = parser.parse_args()

    df = pd.read_csv("F_detections.csv")

    subset = df.iloc[args.start:args.end]

    for _, row in subset.iterrows():
        run_row(row, args.start, args.end)


if __name__ == "__main__":
    main()