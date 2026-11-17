# ==========================================
# Raw Database (external table over the DMS parquet files)
# ==========================================

resource "aws_glue_catalog_database" "raw" {
  name = "stock_raw"
}

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