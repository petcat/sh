import base64
import yaml

TEMPLATE = "template.yaml"
OUTPUT = "config.yaml"
SS_FILE = "ss.txt"

def parse_ss_link(link):
    if not link.startswith("ss://"):
        return None
    link = link[5:]
    if "#" in link:
        link, name = link.split("#", 1)
    else:
        name = "SS"

    try:
        decoded = base64.urlsafe_b64decode(link + "===").decode()
    except Exception:
        return None

    method, rest = decoded.split(":", 1)
    password, rest = rest.split("@", 1)
    server, port = rest.split(":", 1)

    return {
        "name": name,
        "type": "ss",
        "server": server,
        "port": int(port),
        "cipher": method,
        "password": password,
        "udp": True
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

    # 手动拼接单行 { } 格式
    proxy_lines = []
    for node in proxies:
        line = "  - { " + ", ".join(f"{k}: {v}" for k, v in node.items()) + " }"
        proxy_lines.append(line)

    # 写入最终文件
    with open(OUTPUT, "w") as f:
        f.write("proxies:\n")
        for line in proxy_lines:
            f.write(line + "\n")

        f.write("\nproxy-groups:\n")
        f.write("  - name: Proxy\n")
        f.write("    type: select\n")
        f.write("    proxies:\n")
        for name in names:
            f.write(f"      - {name}\n")

    print(f"生成完成：{OUTPUT}")

if __name__ == "__main__":
    main()
