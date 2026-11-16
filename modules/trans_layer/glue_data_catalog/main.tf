# ==========================================
# Bronze Database
# ==========================================

resource "aws_glue_catalog_database" "bronze" {
  name = var.database_name
}

# ==========================================
# Silver Database
# ==========================================

resource "aws_glue_catalog_database" "silver" {
  name = "stock_silver"
}

# ==========================================
# Gold Database
# ==========================================

resource "aws_glue_catalog_database" "gold" {
  name = "stock_gold"
}