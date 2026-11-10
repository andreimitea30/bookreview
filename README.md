# BookReview — Platformă de recenzii cărți

Aplicație bazată pe microservicii care permite utilizatorilor să lase recenzii pentru cărți, cu filtrare automată a limbajului vulgar și calcul automat al mediei notelor.

## Arhitectură

```
Browser
   │
   └── Kong API Gateway (:8000)
         ├── /auth/*  → Auth Service (:5000)
         └── /api/*   → Business Logic Service (:5002)
                              ├── Auth Service (validare JWT)
                              └── IO Service (:5001)
                                      └── MariaDB books-db
```

**Rețele Docker:**
- `auth-network` — auth-service ↔ auth-db
- `app-network` — business-logic ↔ io-service ↔ books-db
- `gateway-network` — kong ↔ auth-service ↔ business-logic
- `monitoring-network` — prometheus ↔ grafana ↔ portainer

---

## Rulare locală (Docker Compose)

Cele trei microservicii sunt incluse ca **git submodules** (repo-uri separate). La clonare folosește `--recurse-submodules`:

```bash
git clone --recurse-submodules -b initial_try https://github.com/andreimitea30/bookreview.git
cd bookreview
```

Dacă ai clonat deja fără submodules:
```bash
git submodule update --init --recursive
```

```bash
# Pornire
docker compose up --build -d

# Oprire
docker compose down

# Logs live
docker compose logs -f
```

**Servicii disponibile local:**

| Serviciu | URL |
|---|---|
| Kong API Gateway | http://localhost:8000 |
| Adminer (DB admin) | http://localhost:8080 |
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |
| Portainer | http://localhost:9000 |

---

## Testare API

### Înregistrare utilizator
```bash
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"user1","email":"user1@test.com","password":"parola123"}'
```

### Login și obținere JWT
```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user1","password":"parola123"}'
# Salvează token-ul din răspuns
```

### Listă cărți
```bash
curl http://localhost:8000/api/books

# Căutare după titlu/autor
curl "http://localhost:8000/api/books?q=tolkien"
```

### Adaugă recenzie (necesită JWT)
```bash
curl -X POST http://localhost:8000/api/reviews \
  -H "Content-Type: application/json" \
  -d '{
    "token": "<JWT_TOKEN>",
    "book_id": 1,
    "rating": 5,
    "comment": "Carte extraordinară!"
  }'
```

### Recenzii pentru o carte
```bash
curl http://localhost:8000/api/books/1/reviews
```

---

## Docker Swarm — Setup cluster

### Cerințe
- 3 mașini (VM/VPS) cu Docker instalat
- Manager: IP public accesibil
- Porturile deschise între noduri: `2377`, `7946`, `4789`

### 1. Inițializare manager

Pe mașina **manager**:
```bash
docker swarm init --advertise-addr <IP_MANAGER>
```

Comanda va afișa un token de join, de forma:
```
docker swarm join --token SWMTKN-1-xxxx <IP_MANAGER>:2377
```

### 2. Join workers

Pe fiecare mașină **worker** (rulează comanda din pasul anterior):
```bash
docker swarm join --token SWMTKN-1-xxxx <IP_MANAGER>:2377
```

### 3. Verificare noduri (pe manager)

```bash
docker node ls
# ID         HOSTNAME   STATUS   AVAILABILITY  MANAGER STATUS
# abc123 *   manager    Ready    Active        Leader
# def456     worker1    Ready    Active
# ghi789     worker2    Ready    Active
```

### 4. Deploy manual al stack-ului

```bash
# Pe manager — clonează repo-ul
git clone <REPO_URL> bookreview
cd bookreview

# Setează variabilele
export DOCKER_USERNAME=<docker_hub_username>
export IMAGE_TAG=latest

# Deploy
docker stack deploy --with-registry-auth --compose-file docker-stack.yml bookreview
```

### 5. Comenzi utile Swarm

```bash
# Status servicii în stack
docker stack services bookreview

# Status task-uri (containere) per serviciu
docker stack ps bookreview

# Scale manual un serviciu
docker service scale bookreview_business-logic-service=3

# Update imagine (rolling update)
docker service update --image <user>/bookreview-auth-service:new_tag bookreview_auth-service

# Rollback la versiunea anterioară
docker service rollback bookreview_auth-service

# Logs serviciu
docker service logs bookreview_auth-service -f

# Oprire stack
docker stack rm bookreview
```

---

## CI/CD — GitHub Actions

La fiecare `push` pe branch-ul `main`, pipeline-ul automat:
1. Construiește imaginile Docker pentru cele 5 servicii
2. Le publică pe Docker Hub cu tag `latest` și `<commit-sha>`
3. Se conectează SSH pe managerul Swarm și rulează `docker stack deploy`

### Secrets necesare în GitHub

Mergi la **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Descriere |
|---|---|
| `DOCKER_USERNAME` | Username Docker Hub |
| `DOCKER_PASSWORD` | Token Docker Hub (nu parola!) — generează din [hub.docker.com/settings/security](https://hub.docker.com/settings/security) |
| `SWARM_HOST` | IP-ul public al managerului Swarm |
| `SWARM_USER` | User SSH pe manager (ex: `ubuntu`) |
| `SWARM_SSH_KEY` | Cheia privată SSH (conținutul fișierului `~/.ssh/id_rsa`) |

### Generare cheie SSH pentru CI/CD

Pe manager:
```bash
# Generează pereche de chei dedicată pentru CI/CD
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions -N ""

# Adaugă cheia publică în authorized_keys pe manager
cat ~/.ssh/github_actions.pub >> ~/.ssh/authorized_keys

# Afișează cheia privată — copiaz-o în GitHub secret SWARM_SSH_KEY
cat ~/.ssh/github_actions
```

---

## Monitoring

### Grafana
- URL: http://\<IP_MANAGER\>:3000
- User/Parolă: `admin` / `admin`
- Adaugă datasource: Prometheus → `http://prometheus:9090`
- Importă dashboard ID `10826` (Flask apps metrics)

### Prometheus
- URL: http://\<IP_MANAGER\>:9090
- Targets activi: `/targets` — ar trebui să vezi toate cele 3 servicii

### Portainer
- URL: http://\<IP_MANAGER\>:9000
- La prima accesare setează parola admin

---

## Imagini Docker Hub

| Imagine | Descriere |
|---|---|
| `<user>/bookreview-auth-service` | Auth Service (Flask) |
| `<user>/bookreview-io-service` | IO Service (Flask) |
| `<user>/bookreview-business-logic-service` | Business Logic (Flask) |
| `<user>/bookreview-auth-db` | MariaDB + schema users |
| `<user>/bookreview-books-db` | MariaDB + schema books/reviews |

---

## Echipă

- **Mitea Andrei-Cristian** (341C4) — Auth Service, Kong, GitHub Actions, Docker Swarm
- **Scîrtocea Bianca-Ioana** (343C1) — Business Logic, IO Service, MariaDB, Prometheus/Grafana, Portainer
