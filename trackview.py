import datetime
import hashlib
import json
from google.cloud import storage
from math import isnan
from urllib.parse import quote

URL_LIFETIME_MIN = 7 * 24 * 60
SCALE = 1
CONFIG_PREFIX = 'ucsc'
TRACK_POSITION = 'chr19:11500000-12000000'
TRACK_WINDOWING = 'mean'
TRACK_VISIBILITY = 'full'
TRACK_MAX_HEIGHT = 70

TrackColor = {
    "Acetyl": "0,150,150",
    "Unknown": "125,125,125",
    "WCE": "0,0,0",
    "Pol2": "0,100,0",
    "H3K4me3": "0,150,0",
    "H3K4me2": "0,130,0",
    "H3K4me1": "0,110,0",
    "H3K27me3": "255,0,0",
    "EZH2": "200,0,0",
    "H3K36me3": "0,0,150",
    "H3K36me2": "0,0,130",
    "H3K9me3": "100,0,0",
    "H3K9me2": "80,0,0",
    "H3K9me1": "30,0,0",
    "H4K20me3": "150,0,0",
    "H3K27ac": "12,71,79",
    "H3K9ac": "85,107,47",
}

def parse_gs_uri(gs_uri):
    """
    Parses a gs:// URI and returns a tuple of (bucket_name, blob_name).
    """
    if not gs_uri.startswith("gs://"):
        raise ValueError("Invalid GCS URI: must start with 'gs://'")
    parts = gs_uri[5:].split("/", 1)
    if len(parts) != 2:
        raise ValueError("Invalid GCS URI: must include bucket and object name")
    return parts[0], parts[1]

def generate_signed_url(bucket_name, blob_name, credentials):
    """
    Generates a v4 signed URL for downloading a blob.
    
    Args:
        bucket_name (str): The name of the bucket containing the blob.
        blob_name (str): The name of the blob to generate the signed URL for.
        service_account_file (str): The path to the service account key file.
    
    Returns:
        str: The generated signed URL.
    
    Note:
        This method requires a service account key file. You cannot use this if you are using Application Default
        Credentials from Google Compute Engine or from the Google Cloud SDK.
    """
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    
    url = blob.generate_signed_url(
        version="v4",
        credentials=credentials,
        # This URL is valid for 7 days
        expiration=datetime.timedelta(minutes=URL_LIFETIME_MIN),
        # Allow GET requests using this URL.
        method="GET"
    )
    
    return url

def get_track_color(track):
    epitope = track.get("epitope")
    if epitope:
        color = TrackColor.get(epitope)
        if color:
            return color
        else:
            return TrackColor["Acetyl"] if epitope.endswith("ac") else TrackColor["Unknown"]
    else:
        return TrackColor["Unknown"]

def get_track_stats(track):
    total_reads = round(track.get("totalFrag", 0) / 1e5) / 10
    pct_aligned = round((track.get("alignedFrag", 0) / track.get("totalFrag", 1)) * 100)
    pct_duplicate = round(track.get("perDupFrag", 0))
    view_max = (track.get("alignedFrag", 0) - track.get("dupFrag", 0)) / 1e6
    return {
        "totalReads": total_reads,
        "pctAligned": pct_aligned,
        "pctDuplicate": pct_duplicate,
        "viewMax": view_max,
    }

def get_track_description(track, stats):
    return " - ".join([
        track.get("library", "NA"),
        track["parent"].replace("Pool Component", "PC") if track["parent"].startswith("Pool Component") else "NA",
        track.get("cellType", "NA"),
        track.get("epitope", "NA"),
        str(stats["totalReads"]) if not isnan(stats["totalReads"]) else "NA",
        f"{stats['pctAligned']}%" if not isnan(stats["pctAligned"]) else "NA",
        f"{stats['pctDuplicate']}%" if not isnan(stats["pctDuplicate"]) else "NA",
    ])

def get_bigwig_track(track, scale, credentials):
    stats = get_track_stats(track)
    description = get_track_description(track, stats)
    bucket, blob = parse_gs_uri(track["bigwig"])
    signed_url = generate_signed_url(bucket, blob, credentials)
    color = get_track_color(track)
    
    auto_scale = scale == "auto"
    if auto_scale:
        view_limits = ""
    else:
        view_max = stats["viewMax"]
        try:
            view_limit = int(view_max * float(scale))
        except (ValueError, TypeError):
            view_limit = 100
        view_limits = f" viewLimits=0:{view_limit}"
    
    return " ".join([
        "track",
        "type=bigWig",
        f'name="{track["track"]}"',
        f'description="{description}"',
        f"windowingFunction={TRACK_WINDOWING}",
        f"visibility={TRACK_VISIBILITY}",
        f"maxHeightPixels={TRACK_MAX_HEIGHT}",
        f"autoScale={'on' if auto_scale else 'off'}" + view_limits,
        f"color={color}",
        f"bigDataUrl={signed_url}"
    ])

def get_config(tracks, credentials):
    header = f"browser position {TRACK_POSITION}"
    lines = [get_bigwig_track(track, SCALE, credentials) for track in tracks]
    return '\n'.join([header] + lines)

def create_config_file(bucket_name, file_name, content, credentials, content_type="text/plain"):
    # Set up credentials and client
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob_name = f'{CONFIG_PREFIX}/{file_name}'
    blob = bucket.blob(blob_name)
    
    # Upload the string content as a file
    blob.upload_from_string(content, content_type=content_type)
    
    # Generate a signed URL to access the uploaded file
    signed_url = generate_signed_url(bucket_name, blob_name, credentials)
    
    return signed_url

def get_redirect_url(db, config_url, session_url):
    
    custom_text = quote(config_url)
    load_url_name = quote(session_url)
    
    query_params = [
        f"db={db}",
        f"hgt.customText={custom_text}",
        "hgS_doLoadUrl=submit",
        f"hgS_loadUrlName={load_url_name}"
    ]
    
    return "https://genome.ucsc.edu/cgi-bin/hgTracks?" + "&".join(query_params)

def get_hash(data):
    json_string = json.dumps(data, sort_keys=True)  # Sort keys to ensure stable hash
    return hashlib.md5(json_string.encode('utf-8')).hexdigest()
