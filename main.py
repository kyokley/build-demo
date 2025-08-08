import os
from subprocess import PIPE, run
from textwrap import wrap
from urllib.parse import quote

import httpx
import uvicorn
from fastapi import FastAPI, Response

FORTUNE_EXEC = os.environ.get("FORTUNE_EXEC") or "/bin/fortune"
app = FastAPI()


@app.get("/")
def main():
    return "Hello from build-demo!"


@app.get("/cat")
def cat():
    fortune = get_fortune()
    url = f"https://cataas.com/cat/cute/says/{fortune}"
    resp = httpx.get(
        url,
        params={
            "html": "true",
            "fontSize": "22",
        },
    )
    print(resp)
    return Response(content=resp.content)


def get_fortune():
    fortune = (
        run([f"{FORTUNE_EXEC}", "-s"], stdout=PIPE, check=True).stdout.decode().strip()
    )
    fortune = wrap(fortune)
    print(fortune)
    return quote("\n".join(fortune))


if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8001, reload=True, workers=1)
