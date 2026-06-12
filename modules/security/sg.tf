# =============================================================================
# modules/security/sg.tf
# 3 Security Groups : alb (public), app (prive), db (prive-DB).
# =============================================================================
# Ressources a declarer :
#
#   - aws_security_group "alb"   (nom alb-sg, vpc_id = var.vpc_id)
#   - aws_security_group "app"   (nom app-sg, vpc_id = var.vpc_id)
#   - aws_security_group "db"    (nom db-sg,  vpc_id = var.vpc_id)
#
#   - aws_vpc_security_group_ingress_rule "alb_https"  : 443 from 0.0.0.0/0
#   - aws_vpc_security_group_ingress_rule "alb_http"   : 80  from 0.0.0.0/0 (redirect)
#   - aws_vpc_security_group_egress_rule  "alb_all"    : -1  to   0.0.0.0/0
#
#   - aws_vpc_security_group_ingress_rule "app_from_alb" : 80 from SG alb
#                                                          (referenced_security_group_id)
#   - aws_vpc_security_group_egress_rule  "app_all"      : -1 to   0.0.0.0/0
#
#   - aws_vpc_security_group_ingress_rule "db_from_app"  : 5432 TCP from SG app
#                                                          (referenced_security_group_id)
#
# 🟡 Rappel syntaxe v5+ : depuis le provider AWS 5.x, on utilise des ressources
#   separees aws_vpc_security_group_ingress_rule / _egress_rule (et non plus les
#   blocs ingress {} / egress {} dans aws_security_group).
#
# Pattern inter-SG : pour autoriser "app" depuis "alb", on utilise :
#   referenced_security_group_id = aws_security_group.alb.id
#   (et PAS cidr_ipv4 — les 2 arguments sont exclusifs)
# =============================================================================

# =============================================================================
# Security Groups : alb (public), app (private), db (private-DB)
# =============================================================================

# -----------------------------------------------------------------------------
# SG ALB (public)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security Group du Load Balancer (public)"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# HTTP (80) depuis Internet
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# HTTPS (443) depuis Internet
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Egress ALB : tout vers Internet
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# SG APP (instances privées)
# -----------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Security Group des instances applicatives"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-sg"
  })
}

# APP : HTTP (80) depuis ALB
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

# Egress APP : tout vers Internet
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# SG DB (PostgreSQL privé)
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "Security Group de la base de donnees"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-sg"
  })
}

# DB : PostgreSQL (5432) depuis APP
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

