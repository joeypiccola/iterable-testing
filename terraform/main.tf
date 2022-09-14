resource "local_file" "test" {
    content  = var.content
    filename = "~/${var.filename}"
}