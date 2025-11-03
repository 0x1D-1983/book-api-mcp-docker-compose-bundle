-- BookApi Database Setup Script for pgAdmin
-- This script creates the database and table structure for the BookApi application

-- Create the database (run this first in pgAdmin)
CREATE DATABASE bookapi;

-- Connect to the bookapi database, then run the following:

-- Create the books table
CREATE TABLE IF NOT EXISTS books (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    author VARCHAR(300) NOT NULL,
    isbn VARCHAR(20),
    published_date TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_books_author ON books(author);
CREATE INDEX IF NOT EXISTS idx_books_isbn ON books(isbn);
CREATE INDEX IF NOT EXISTS idx_books_created_at ON books(created_at);

-- Optional: If you want to use TimescaleDB hypertable features for time-series queries
-- You can convert the table to a hypertable by uncommenting the following:
-- SELECT create_hypertable('books', 'created_at', if_not_exists => TRUE);

-- Sample data for testing
INSERT INTO books (title, author, isbn, published_date, created_at) VALUES
('The Great Gatsby', 'F. Scott Fitzgerald', '978-0743273565', '1925-04-10 00:00:00', CURRENT_TIMESTAMP),
('To Kill a Mockingbird', 'Harper Lee', '978-0061120084', '1960-07-11 00:00:00', CURRENT_TIMESTAMP),
('1984', 'George Orwell', '978-0451524935', '1949-06-08 00:00:00', CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;

-- Verify the table was created correctly
SELECT * FROM books;

