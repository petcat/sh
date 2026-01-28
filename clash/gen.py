import base64
import yaml
import re

TEMPLATE = "template.yaml"
OUTPUT = "config.yaml"
SS_FILE = "ss.txt"

def parse_ss_link(link):
    # ss://base64(method:password@server:port)#name
    if not link.startswith("ss://"):
        return None

    link = link[5:]
    if "#" in link:
        link, name = link.split("#", 1)
    else:
        name = "SS"

    decoded = base64.urlsafe_b64decode(link + "===").decode()
    method, rest = decoded.split(":", 1)
    password, rest = rest.split("@", 1)
    server, port = rest.split(":", 1)

    return {
        "name": name,
        "type": "ss",
        "server": server,
        "port": int(port),
        "cipher": method,
        "password": password
    }

def load_template():
    with open(TEMPLATE, "r") as f:
        return yaml.safe_load(f)

def main():
    config = load_template()
    proxies = []
    names = []

    with open(SS_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            node = parse_ss_link(line)
            if node:
                proxies.append(node)
                names.append(node["name"])

    config["proxies"] = proxies
    config["proxy-groups"][0]["proxies"] = names

    with open(OUTPUT, "w") as f:
        yaml.dump(config, f, allow_unicode=True)

    print(f"生成完成：{OUTPUT}")

if __name__ == "__main__":
    main()
