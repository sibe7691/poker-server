"""Structured logging configuration."""
import logging
import sys
from typing import Optional

from src.config import config


def get_logger(name: Optional[str] = None) -> logging.Logger:
    """Get a configured logger instance.
    
    Args:
        name: Logger name, typically __name__ of the calling module.
        
    Returns:
        Configured logger instance.
    """
    logger = logging.getLogger(name or "poker")
    
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(
            "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(getattr(logging, config.log_level.upper(), logging.INFO))
    
    return logger
