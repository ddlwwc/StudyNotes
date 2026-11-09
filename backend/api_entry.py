import os

import uvicorn

from main import app


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=os.environ.get("STUDY_NOTES_API_HOST", "127.0.0.1"),
        port=int(os.environ.get("STUDY_NOTES_BACKEND_PORT", "8765")),
    )
