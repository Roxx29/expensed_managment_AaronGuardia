/// Simple email shape check (local@domain.tld). Not a full RFC validator.
final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
