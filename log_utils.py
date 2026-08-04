def log_progress(message, **fields):
    details = " ".join(f"{key}={value}" for key, value in fields.items())
    print(f"{message}: {details}" if details else message, flush=True)
