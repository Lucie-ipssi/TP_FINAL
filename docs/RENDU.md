# RENDU — TP05 — Nextcloud sur AWS

> **Instructions de remplissage** : ce fichier est le `docs/RENDU.md` à livrer dans votre zip. Copiez-le tel quel dans votre repo à la racine de `docs/RENDU.md`, puis remplissez **toutes** les sections ci-dessous. Les `<!-- remplir ici -->` et les `TODO` doivent avoir disparu à la remise.

---

## 🟥 Rappel critique — avant de zipper

> 🟥 **Ne jamais committer** :
>
> - `*.tfvars` (sauf les `*.tfvars.example`)
> - `*.tfstate` et `*.tfstate.backup`
> - Le dossier `.terraform/`
> - Aucun mot de passe en clair (DB, admin Nextcloud, clé AWS, token GitHub)
> - Aucune clé privée (`*.pem`, `id_rsa`, etc.)
>
> 🔹 Vérifiez une dernière fois avant le zip :
>
> ```bash
> cd tp05-nextcloud
> grep -rE "(password|secret|AKIA)" --include="*.tf" --include="*.tfvars" . | grep -v example
> # Doit retourner 0 ligne
> ```

---

## Section 1 — Identification de l'équipe

**Numéro d'équipe** : `TODO`
**Nom de code de l'équipe** *(optionnel)* : `TODO`
**Date de rendu** : `YYYY-MM-DD`

### Membres

| Prénom Nom | Rôle assigné | Email | Compte GitHub |
|------------|--------------|-------|---------------|
| `Lucie Bigouraux` | Platform Lead (Rôle 1) | `l.bigouraux@ecole-ipssi.net` | `lucie-ipssi` |
| `Fatima El Haouza` | Network Engineer (Rôle 2) | `elhaouzafatimazahra@gmail.com`| `elhaouzafatimazahra-jpg` |
| `Yann Neguen` | Compute Engineer (Rôle 3) |`neguenyann4@gmail.com` |  `neguenyann`|
| `Junias Gbenou` | Data Engineer (Rôle 4) |`juniasgbenou0@gmail.com` |`jxnxas-gb` |
| `Lucie Bigouraux` | Security Engineer (Rôle 5) | `l.bigouraux@ecole-ipssi.net`| `lucie-ipssi` |

> 🔷 Équipe à 4 personnes : indiquez qui a fusionné le rôle Security dans le rôle Platform.
>
> *Exemple : "Équipe à 4 — le Platform Lead a également porté le module `security`."*

---

## Section 2 — Résumé architecture
VPC 10.30.0.0/16 sur 2 AZ (eu-west-3a, eu-west-3b) avec 6 subnets (2 publics, 2 app, 2 db). ALB public HTTPS self-signed → ASG d'une EC2 t3.small privée qui exécute Nextcloud en container Docker. RDS PostgreSQL Multi-AZ en subnet db, avec rds.force_ssl activé. Stockage primaire S3 chiffré KMS (CMK), logs ALB sur second bucket S3 chiffré AES256 avec cycle de vie Glacier. Secrets DB et admin Nextcloud dans Secrets Manager, lus par l'EC2 via IAM Instance Profile (IMDSv2) au boot, avec VPC Endpoints S3/Secrets Manager/KMS pour limiter le trafic NAT.
**En 5 lignes maximum**, décrivez l'infrastructure déployée (couches, AZ, interactions principales).

> *Exemple attendu :*
> *VPC 10.30.0.0/16 sur 2 AZ (eu-west-1a, eu-west-1b) avec 6 subnets (2 publics, 2 app, 2 db). ALB public HTTPS self-signed → ASG d'une EC2 t3.small privée qui exécute Nextcloud en container Docker. RDS PostgreSQL 16 Multi-AZ en subnet db. Stockage primaire S3 chiffré KMS, logs ALB sur second bucket S3. Secrets DB et admin dans Secrets Manager, lus par l'EC2 via IAM Instance Profile au boot.*

<!-- remplir ici -->

### Schéma Mermaid (à jour avec ce qui a été réellement déployé)

flowchart TB
    t_user((Utilisateur))

    subgraph t_internet[Internet]
        t_dns[DNS public ALB]
    end

    subgraph t_vpc[VPC 10.30.0.0/16 eu-west-3]
        subgraph t_public[Subnets publics AZ-a / AZ-b]
            t_alb[ALB HTTPS 443<br/>self-signed cert]
            t_nat[NAT Gateway]
        end

        subgraph t_private_app[Subnets prives app AZ-a / AZ-b]
            t_asg[ASG single EC2<br/>Docker + Nextcloud]
        end

        subgraph t_private_db[Subnets prives db AZ-a / AZ-b]
            t_rds[(RDS PostgreSQL<br/>Multi-AZ)]
        end

        t_vpce_s3[VPC Endpoint S3]
        t_vpce_secrets[VPC Endpoint Secrets Manager]
        t_vpce_kms[VPC Endpoint KMS]
    end

    subgraph t_aws[Services AWS regionaux]
        t_s3_primary[S3 primary storage<br/>fichiers Nextcloud<br/>KMS]
        t_s3_logs[S3 ALB logs<br/>AES256 + Glacier]
        t_secrets[Secrets Manager<br/>db_pwd + admin_pwd]
        t_kms[KMS CMK<br/>rotation activee]
    end

    t_user --> t_dns
    t_dns --> t_alb
    t_alb --> t_asg
    t_asg --> t_rds
    t_asg -->|IAM role| t_vpce_s3
    t_vpce_s3 --> t_s3_primary
    t_asg -->|IAM role| t_vpce_secrets
    t_vpce_secrets --> t_secrets
    t_asg -->|IAM role| t_vpce_kms
    t_vpce_kms --> t_kms
    t_alb -->|access logs| t_s3_logs
    t_asg -->|egress updates| t_nat

    t_kms -.chiffre.-> t_s3_primary
    t_kms -.chiffre.-> t_rds
    t_kms -.chiffre.-> t_secrets

    classDef alb fill:#fff3cd,stroke:#ffc107
    classDef app fill:#d1e7dd,stroke:#198754
    classDef data fill:#cfe2ff,stroke:#0d6efd
    classDef sec fill:#f8d7da,stroke:#dc3545
    class t_alb,t_dns alb
    class t_asg,t_nat app
    class t_rds,t_s3_primary,t_s3_logs data
    class t_secrets,t_kms,t_vpce_s3,t_vpce_secrets,t_vpce_kms sec

> 🔹 Astuce : copiez le schéma du fichier `ARCHITECTURE.md` que vous avez maintenu pendant la journée.

---

## Section 3 — Arbitrages techniques réalisés

Listez **au minimum 3 arbitrages** que vous avez faits pendant le TP (choix structurant, alternative considérée, raison du choix, conséquence).

### Arbitrage 1

- **Choix retenu** : ASG à instance unique (`min=1 max=2 desired=1`).
- **Alternative envisagée** : 2 instances actives derrière l'ALB.
- **Raison** : Nextcloud sans Redis/cluster verrouille les fichiers au niveau disque — deux instances actives entraîneraient des erreurs de file locking sur le stockage S3 partagé.
- **Conséquence / limite** : pas de haute disponibilité applicative sur ce TP, mais l'ASG redémarre automatiquement l'instance en cas de crash.

> *Exemple :*
>
> - *Choix retenu : ASG à instance unique (`min=1 max=2 desired=1`).*
> - *Alternative envisagée : 2 instances actives derrière l'ALB.*
> - *Raison : Nextcloud sans Redis/cluster verrouille les fichiers au niveau disque — deux instances actives entraîneraient des erreurs de file locking sur le stockage S3 partagé.*
> - *Conséquence : pas de haute disponibilité applicative sur ce TP, mais l'ASG redémarre automatiquement l'instance en cas de crash.*

### Arbitrage 2

- **Choix retenu** : certificat self-signed via `tls_private_key` + `aws_acm_certificate` (import) au lieu d'ACM public.
- **Alternative envisagée** : certificat ACM public validé par Route53.
- **Raison** : pas de domaine validé par Route53 disponible pour ce TP.
- **Conséquence / limite** : warning navigateur accepté volontairement pour la démo (visible sur le screenshot login).


> *Exemple : certificat self-signed via `tls_private_key` + `aws_acm_certificate` (import) au lieu d'ACM public, parce qu'on n'a pas de domaine validé par Route53 — conséquence : warning navigateur accepté volontairement pour la démo.*

### Arbitrage 3

- **Choix retenu** : `single_nat_gateway = true` (1 seule NAT Gateway, AZ-a).
- **Alternative envisagée** : 2 NAT Gateways (1 par AZ) pour la haute disponibilité sortante.
- **Raison** : réduire le coût d'environ 30€/jour pour rester dans le budget cible (<150€/jour).
- **Conséquence / limite** : perte de la HA sortante (si l'AZ-a tombe, plus de sortie Internet pour les subnets privés), acceptable en `dev`.


> *Exemple : `single_nat_gateway = true` pour éviter le coût de 2 NAT Gateway sur la journée — conséquence : perte de la HA sortante, acceptable en `dev`.*

### Arbitrages supplémentaires *(optionnels)*
- **Choix retenu** : utilisation de VPC Endpoints (S3 Gateway gratuit, Secrets Manager et KMS Interface) plutôt que tout faire passer par la NAT Gateway.
- **Alternative envisagée** : laisser tout le trafic AWS sortir via NAT.
- **Raison** : réduire le coût NAT et améliorer la sécurité (pas de sortie Internet pour ces flux sensibles).
- **Conséquence / limite** : coût supplémentaire des interface endpoints (~0.01$/h chacun), mais compensé par la baisse de trafic NAT.
---

## Section 4 — Retour sur les interfaces inter-modules

Les interfaces (variables + outputs) étaient figées au kick-off. Répondez aux questions suivantes.

**Quelle interface a été la plus délicate à stabiliser ?**

> *Exemple : l'interface `security` ↔ `data` à cause du cycle (security a besoin des ARN S3, data a besoin du KMS ARN). On a résolu en passant les ARN S3 en variable de `security` (late binding via `module.data.s3_primary_bucket_arn`).*

<!-- L'interface `security` ↔ `data` : le module security a besoin des ARN des buckets S3 (pour les policies IAM), tandis que le module data a besoin de l'ARN de la clé KMS pour chiffrer ses ressources. On a résolu en passant les ARN S3 en variable de `security` après création des buckets dans `data` (late binding via `module.data.s3_primary_bucket_arn`). --> 

**Avez-vous dû modifier une interface en cours de route ? Si oui, laquelle et pourquoi ?**

> *Exemple : ajout de la variable `trusted_domain` en entrée du module compute, oubliée dans le contrat initial. PR #12 mergée après review du Platform Lead.*

<!-- Oui, le module networking a initialement été livré avec un endpoint Secrets Manager uniquement, mais un VPC Endpoint KMS a été ajouté en cours de route (outputs enrichis) pour que l'EC2 puisse déchiffrer les secrets via KMS sans passer par la NAT. -->

**Qu'est-ce qui a le mieux fonctionné dans la collaboration inter-modules ?**

> *Exemple : le fait d'écrire les outputs en premier (avant les resources) a permis aux autres rôles de `plan` avec des valeurs fictives et avancer en parallèle.*

<!-- Le fait d'avoir des interfaces (variables.tf + outputs.tf) figées et écrites avant les ressources a permis à chaque rôle de travailler en parallèle dès le départ : le rôle Network a livré ses outputs (vpc_id, subnet_ids) en premier, ce qui a débloqué immédiatement les rôles Compute et Data.-->

**Qu'est-ce qui a bloqué ?**

<!-- La gestion des permissions Git (accès en écriture au repo GitHub) a pris du temps pour certains membres de l'équipe avant de pouvoir push leurs branches. -->

---

## Section 5 — Résultats `terraform plan` et `terraform apply`

Collez ici les **résumés** (pas les sorties complètes) des commandes finales exécutées depuis `envs/dev/`.

### `terraform plan` final

```text
Terraform will perform the following actions:
  ...

Plan: <!-- N --> to add, <!-- N --> to change, <!-- N --> to destroy.
```

### `terraform apply` final

```text
Apply complete! Resources: <!-- N --> added, <!-- N --> changed, <!-- N --> destroyed.

Outputs:

alb_dns_name  = "<!-- remplir -->"
nextcloud_url = "<!-- remplir -->"
db_endpoint   = "<!-- remplir -->"
# ... autres outputs
```

### Nombre total de ressources déployées

**Total** : `<!-- N -->` ressources

> 🔷 Ce nombre doit correspondre à ce qui est visible dans `02-apply-success.png`.

---

## Section 6 — Checklist des 5 screenshots obligatoires

Les captures doivent être dans `docs/screenshots/` au format PNG. Cochez chaque case quand le fichier est présent ET lisible.

- [ ] `01-plan-dev.png` — sortie de `terraform plan` avec la ligne `Plan: N to add, ...` visible
- [ ] `02-apply-success.png` — sortie `Apply complete! Resources: N added.` + les outputs visibles
- [ ] `03-nextcloud-login.png` — page de login Nextcloud dans le navigateur avec l'URL ALB visible dans la barre d'adresse
- [ ] `04-file-in-s3.png` — console AWS S3 montrant un fichier uploadé depuis Nextcloud, avec le chiffrement KMS visible dans les propriétés
- [ ] `05-destroy-success.png` — sortie `Destroy complete! Resources: N destroyed.`

> 🟡 Piège courant : les screenshots avec informations sensibles visibles. Avant de les coller dans le zip, floutez les IP publiques personnelles, les tokens, les clés AWS complètes.

> 🔹 Astuce : si une capture contient un mot de passe admin Nextcloud en clair (généré puis affiché), régénérez-la avec le mot de passe masqué ou ne l'incluez pas.

---

## Section 7 — Coût estimé

Estimez le coût de l'infrastructure pour 24h de fonctionnement (dev). Utilisez Infracost si possible, sinon faites un calcul manuel à partir de la [page de tarification AWS eu-west-1](https://aws.amazon.com/ec2/pricing/on-demand/).

| Ressource | Quantité | Prix unitaire (USD) | Sous-total 24h (USD) |
|-----------|----------|---------------------|----------------------|
| EC2 t3.small | `<!-- 1 -->` | `<!-- 0.0208/h -->` | `<!-- 50 -->` |
| ALB | 1 | `<!-- 0.0252/h + LCU-->` | `<!-- 70 -->` |
| NAT Gateway | `<!-- 1 ou 2 -->` | `<!-- 0.048/h -->` | `<!-- 1.15 -->` |
| RDS db.t3.micro Multi-AZ | 1 | `<!-- 0.034/h -->` | `<!-- 0.82 -->` |
| EBS RDS gp3 | `<!-- 20GB -->` | `<!-- 0.0029/GB-mois -->` | `<!-- 0.06 -->` |
| S3 primary + logs | `<!-- 1 GB -->` | `<!-- 0.0008/GB-mois -->` | `<!-- 0.01 -->` |
| KMS CMK | 1 | `1.00 / mois` | `<!-- 0.03 -->` |
| Secrets Manager | 2 | `0.40 / secret / mois` | `<!-- 0.03-->` |
| VPC Endpoints | `<!-- 2 -->` | `<!-- 0.01/h -->` | `<!-- 48 -->` |
| **Total 24h** | | | `<!-- 3.78 -->` |
| **Extrapolation 30 jours** | | | `<!-- 113 -->` |

> *Exemple : Total 24h ~= 6.10 USD, extrapolation 30 jours ~= 183 USD.*

**Méthode utilisée** :estimation manuelle à partir de la page de tarification AWS eu-west-3 (Paris).

**Commentaire** :

> *Exemple : le NAT Gateway seul représente ~35% du coût — on pourrait le supprimer après le boot initial de Nextcloud en `dev` puisque l'instance n'a plus besoin de sortir d'Internet.*

<!-- Le NAT Gateway et les VPC Endpoints Interface représentent ensemble plus de 40% du coût journalier. En production, on pourrait envisager de supprimer le NAT Gateway après le boot initial de l'EC2 (puisque le trafic S3/Secrets/KMS passe déjà par les endpoints dédiés), ce qui réduirait encore le coût mensuel. -->

---

## Section 8 — Rétrospective équipe

### 🟢 3 choses qui ont bien marché

1. Le fait de figer les interfaces (variables/outputs) au kick-off a permis à chaque rôle de travailler en parallèle sans se bloquer mutuellement.
2. La répartition claire des modules (networking, compute, data, security) a évité les conflits Git majeurs sur les fichiers `.tf`.
3. Le starter kit fourni (arborescence + providers déjà configurés) a fait gagner un temps précieux en début de journée.

> *Exemple : "Le fait de figer les interfaces au kick-off nous a permis de travailler en parallèle sans se marcher dessus."*

### 🔴 3 choses qui ont bloqué


1. La configuration initiale de l'environnement (versions Terraform incompatibles, mise à jour manuelle du binaire pour certains membres).
2. La gestion des droits d'accès GitHub (permissions de push sur les branches de rôle) a pris du temps à résoudre.
3. La correction tardive des régions `eu-west-1` → `eu-west-3` dans plusieurs fichiers du starter, qu'il a fallu identifier et corriger après coup.
> *Exemple : "Cycle de dépendance entre security et data — perdu 45 min avant de comprendre qu'il fallait passer les ARN en variable plutôt que `depends_on`."

### 🔷 3 améliorations pour la prochaine fois

1. Vérifier dès le matin les versions des outils (Terraform, AWS CLI) et les droits Git de chaque membre avant de commencer.
2. Faire une relecture collective du starter kit pour repérer toutes les références régionales incorrectes avant de répartir les rôles.
3. Mettre en place un canal de communication dédié pour signaler immédiatement les changements d'interface entre modules.

> *Exemple : "nstaller tfsec dans le pre-commit dès le matin aurait évité 3 HIGH détectés en fin de journée."*

---

## Section 9 — Contribution individuelle par rôle

**Chaque membre remplit son bloc lui-même.** Soyez honnêtes — cette section sert à l'individualisation de la note.

> 🔷 Le hash du commit est obtenu avec `git log --oneline -1 --author="Votre Nom"` ou `git log --format='%h %s' | head -5`.

---

### Rôle 1 — Platform Lead

**Membre** : `<!--Lucie Bigouraux -->`

**Ce que j'ai livré** :
bootstrap/create-state-bucket.sh
nvs/dev/backend.tf, providers.tf, main.tf
la gestion du GitHub de base
**Ce qui m'a surpris ou frustré** :

> *Exemple : "J'ai sous-estimé le temps de bootstrap du bucket state — 15 min à cause d'une IAM policy S3 manquante pour KMS."*

<!-- La mise en place un peu longue
  -->

**Ce que j'ai appris** :

> *Exemple : "La feature `use_lockfile` du backend S3 natif en 1.10 remplace complètement DynamoDB — plus simple et moins cher."*

<!-- une meilleur compréhension de GitHub -->

**Hash du dernier commit significatif que j'ai fait** : `<!-- ex: a1b2c3d -->`

---

### Rôle 2 — Network Engineer

**Membre :** Fatima El Haouza

**Ce que j'ai livré :**
- `modules/networking/main.tf` — VPC (10.30.0.0/16) + 6 subnets (2 publics, 2 privés app, 2 privés DB) sur 2 AZ
- Internet Gateway + NAT Gateway (single AZ, dans le subnet public AZ-a)
- Route tables publique (vers IGW) et privée (vers NAT) + 6 associations de subnets
- Security group pour les VPC endpoints (443 depuis le CIDR du VPC)
- 3 VPC Endpoints : Gateway S3 (gratuit), Interface Secrets Manager et Interface KMS (DNS privé activé)
- Correction de `variables.tf` : AZ par défaut passées de `eu-west-1a/1b` à `eu-west-3a/3b`
- Outputs `vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_app_subnet_ids`, `private_db_subnet_ids`, `nat_gateway_public_ip`, `vpc_endpoints_security_group_id`

**Ce qui m'a surpris ou frustré :**
La différence entre les VPC endpoints de type Gateway (S3, gratuit, ajoute juste une route) et Interface (Secrets Manager / KMS, payants, créent une ENI avec IP privée). J'ai aussi eu un souci avec ma version de Terraform (1.7.5) qui n'était pas compatible avec `required_version >= 1.10.0` — il a fallu mettre à jour le binaire manuellement.

**Ce que j'ai appris :**
À structurer un module Terraform en plusieurs fichiers (variables, outputs, locals, main, versions), à utiliser `for_each` avec des maps AZ → CIDR calculées via `cidrsubnet()`, et le rôle des VPC endpoints pour réduire le trafic NAT.

**Hash du dernier commit significatif que j'ai fait :** `137ee78`


### Rôle 3 — Compute Engineer

**Membre** : `<!-- Yann Neguen -->`

**Ce que j'ai livré** :

-modules/computes/main.tf   data AMI Amazon Linux 2023 + data aws_region + certificat TLS self-signed RSA 4096 + import ACM
 
- modules/computes/main.tf  ALB public + Target Group (health check /status.php) + listener HTTPS/443 + redirect HTTP/80 → 443  .                       
-modules/computes/asg.tf   Launch Template (IMDSv2 obligatoire, EBS gp3 chiffré) + ASG min=1 max=2 desired=1                                             templates/nextcloud-user-data.sh.tfpl  script boot EC2 : install Docker, attente RDS, récupération secrets via Secrets Manager, docker run nextcloud:30-apache

**Ce qui m'a surpris ou frustré** :

> *Exemple : "Le user_data a mis 4 minutes à finir — il faut attendre l'install Docker + pull de l'image Nextcloud avant que le health check ALB passe."*

<!-- remplir ici --> Le http_putresponse_hop_limit dans les metadata_options est indispensable pour que le container Docker puisse accéder à l'IMDS et récupérer les credentials IAM — sans ça Nextcloud ne peut pas écrire sur S3

**Ce que j'ai appris** :

<!-- remplir ici -->La syntaxe du template .tfpl est piégeuse  ,{var} est interprété par Terraform mais $$var est necessaire pour les variables bash, une confusion entre les deux casse silencieusement le script au boot de l'EC2."

**Hash du dernier commit significatif que j'ai fait** : `<!-- 5144327-->`

---

### Rôle 4 — Data Engineer

**Membre** : `<!-- Junias Gbenou -->`

**Ce que j'ai livré** :

- modules/data/rds.tf — RDS PostgreSQL Multi-AZ, subnet group, et parameter group avec rds.force_ssl activé.
- modules/data/s3.tf — Bucket primary (stockage Nextcloud avec versioning et chiffrement KMS via CMK) et Bucket logs (access logs ALB avec chiffrement SSE-AES256 standard, blocage des accès publics complet, et règle de cycle de vie Glacier).
- modules/data/main.tf, variables.tf, outputs.tf, versions.tf — Répartition et clean-up complet de l'architecture du module pour respecter les standards Terraform.
- outputs : db_endpoint, db_port, db_name, db_username, s3_primary_bucket_name, s3_primary_bucket_arn, s3_logs_bucket_name, s3_logs_bucket_arn.

**Ce qui m'a surpris ou frustré** :

> *Exemple : "La bucket policy pour laisser l'ALB écrire ses access logs — il faut utiliser le service principal correct et autoriser PutObject."*

<!-- remplir ici --> La configuration de la bucket policy pour les access logs de l'ALB : il a fallu s'assurer d'utiliser l'identifiant de compte de service ELB AWS correct (via la data source aws_elb_service_account) et forcer l'utilisation de l'algorithme AES256 à la place de KMS, car l'ALB refuse nativement d'écrire sur du S3 chiffré par une clé KMS personnalisée.

**Ce que j'ai appris** :

<!-- remplir ici --> J'ai appris à structurer proprement un module Terraform en séparant rigoureusement les variables, les outputs, la logique de base et les versions de providers, plutôt que de tout centraliser dans un seul fichier. J'ai aussi pratiqué la récupération de commits et la résolution d'arborescences de branches via le Git Reflog et le reset hard lors d'un incident de synchronisation locale.

**Hash du dernier commit significatif que j'ai fait** : `<!-- ex: a1b2c3d -->`24a8a0a

---

### Rôle 5 — Security Engineer

**Membre** : `<!-- Lucie Bigouraux  — ou "N/A équipe à 4, fusionné avec Rôle 1" -->`

**Ce que j'ai livré** :

modules/security/sg.tf
modules/security/kms.tf
modules/security/iam.tf
modules/security/secrets.tf

**Ce qui m'a surpris ou frustré** :

> *Exemple : "La policy IAM avec `Resource` scoped au bucket ARN exact + `${arn}/*` pour les objets — tfsec flag tous les `Resource = *`."*

<!-- la redondance -->

**Ce que j'ai appris** :

<!-- remplir ici --> 
une meilleurs connaissance des différents point de sécurité

**Hash du dernier commit significatif que j'ai fait** : `<!-- ex: a1b2c3d -->`

---

## Section 10 — Checklist finale avant remise

**L'équipe certifie collectivement que** :

- [ ] `terraform destroy` a été exécuté avec succès dans `envs/dev/` (screenshot `05-destroy-success.png` prouve `Destroy complete!`)
- [ ] La console AWS a été re-vérifiée : aucune EC2, RDS, NAT Gateway, ELB, EIP, Secret Manager, bucket S3 (hors bucket state) ne reste avec les tags de l'équipe
- [ ] Aucun fichier `*.tfstate` ou `*.tfstate.backup` n'est présent dans le zip
- [ ] Aucun dossier `.terraform/` n'est présent dans le zip
- [ ] Aucun fichier `*.tfvars` personnel n'est présent (seul `terraform.tfvars.example` est autorisé)
- [ ] Aucun secret en clair (mot de passe DB, admin, access key, token GitHub) n'est dans le code
- [ ] La commande `grep -rE "(password|secret|AKIA)" --include="*.tf" . | grep -v example` retourne 0 ligne
- [ ] Les 5 screenshots obligatoires sont dans `docs/screenshots/`
- [ ] Le fichier `docs/RENDU.md` (ce fichier) est rempli à 100 % — plus aucun `<!-- remplir -->` ni `TODO` résiduel
- [ ] Le fichier `ARCHITECTURE.md` contient un schéma Mermaid à jour
- [ ] Chaque module dans `modules/` a son `README.md` (minimum : titre + description + inputs/outputs)
- [ ] Le fichier `.terraform.lock.hcl` est committé (mais pas `.terraform/`)
- [ ] Les commits git sont tracés par auteur (pour la notation individuelle)
- [ ] Le zip est nommé exactement `tp05-nextcloud-equipe<N>.zip`

### Commande de packaging recommandée

```bash
# Depuis la racine du projet
cd ~/formation-terraform/jour5

# Nettoyage des artefacts lourds avant zip
find tp05-nextcloud -type d -name ".terraform" -exec rm -rf {} +
find tp05-nextcloud -name "terraform.tfstate*" -delete
find tp05-nextcloud -name "*.tfvars" ! -name "*.tfvars.example" -delete

# Verification finale secrets
grep -rE "(password|secret|AKIA)" tp05-nextcloud --include="*.tf" --include="*.tfvars" | grep -v example
# Doit retourner 0 ligne

# Zip final (en conservant le .git pour la notation individuelle)
zip -r tp05-nextcloud-equipe<N>.zip tp05-nextcloud/

# Verification du contenu
unzip -l tp05-nextcloud-equipe<N>.zip | head -50
```

---

## Signature de l'équipe

**Date de remise** : `YYYY-MM-DD HH:MM`

**Signataires** (tous les membres doivent cocher) :

- [ ] `<!-- Prénom Nom Rôle 1 -->` — certifie l'exactitude des informations ci-dessus
- [ ] `<!-- Prénom Nom Rôle 2 -->` — certifie l'exactitude des informations ci-dessus
- [ ] `<!-- Prénom Nom Rôle 3 -->` — certifie l'exactitude des informations ci-dessus
- [ ] `<!-- Prénom Nom Rôle 4 -->` — certifie l'exactitude des informations ci-dessus
- [ ] `<!-- Prénom Nom Rôle 5 -->` — certifie l'exactitude des informations ci-dessus

> 🟢 Bravo — vous avez livré une infrastructure de production réelle en équipe. C'est exactement ce que vous ferez en entreprise. Bon courage pour la suite.
