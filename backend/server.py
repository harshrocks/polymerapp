import os
import requests
import uuid
from typing import List, Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import random
import asyncio
import motor.motor_asyncio
from pymongo import MongoClient

app = FastAPI(title="Polymer Pricing API")

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MongoDB Configuration
MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
DB_NAME = os.getenv("DB_NAME", "polymer_pricing")

try:
    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]
    print(f"Connected to MongoDB: {MONGO_URL}")
except Exception as e:
    print(f"MongoDB connection error: {e}")
    client = None
    db = None

# Pydantic Models
class PolymerPrice(BaseModel):
    id: str
    product: str
    price_range: str
    min_price: float
    max_price: float
    price_change: float
    price_change_percent: str
    transit_time: str
    last_updated: datetime
    location: str = "India"
    currency: str = "INR"

class PriceHistory(BaseModel):
    product: str
    date: datetime
    price: float
    
class LocationFilter(BaseModel):
    location: str
    polymer_types: List[str]

# Sample locations for the app
LOCATIONS = [
    "Mumbai", "Delhi", "Chennai", "Bangalore", "Kolkata", 
    "Ahmedabad", "Pune", "Hyderabad", "Indore", "Vadodara"
]

# Helper function to parse price range
def parse_price_range(price_range: str):
    try:
        # Remove currency symbol and split by '-'
        clean_range = price_range.replace('₹', '').strip()
        parts = clean_range.split(' - ')
        if len(parts) == 2:
            min_price = float(parts[0].strip())
            max_price = float(parts[1].strip())
            return min_price, max_price
        return 0.0, 0.0
    except:
        return 0.0, 0.0

# Mock price change calculation
def calculate_price_change():
    change = random.uniform(-5.0, 3.0)
    return change, f"{change:+.2f}%"

# Scraping function (simulated with actual source.one data)
async def get_source_one_prices():
    """
    Simulated scraping function using the actual data from source.one
    In production, this would use requests + BeautifulSoup to scrape live data
    """
    # Real data from source.one as of scraping
    source_data = [
        {"product": "HD GPBM", "price_range": "₹89 - ₹92.75", "transit_time": "1 DAY"},
        {"product": "ABS MOULD >30 MFI", "price_range": "₹151 - ₹157", "transit_time": "2 DAY"},
        {"product": "ABS MOULD 10-30 MFI", "price_range": "₹143.65 - ₹226.2", "transit_time": "3 DAY"},
        {"product": "BOPP FILM", "price_range": "₹97.3 - ₹99.65", "transit_time": "2 DAYS"},
        {"product": "EVA >=22% VA", "price_range": "₹121.95 - ₹132.15", "transit_time": "1 DAY"},
        {"product": "EVA 18% VA", "price_range": "₹107.7 - ₹114.85", "transit_time": "2 DAYS"},
        {"product": "HD FILM", "price_range": "₹91.2 - ₹103.25", "transit_time": "1 DAY"},
        {"product": "HD HM", "price_range": "₹91.7 - ₹93.45", "transit_time": "2 DAYS"},
        {"product": "HD MBM / LBM", "price_range": "₹92.25 - ₹96.01", "transit_time": "1 DAY"},
        {"product": "HD MOULD < 10MI", "price_range": "₹87.65 - ₹93.25", "transit_time": "1 DAY"},
        {"product": "HD MOULD > 10MI", "price_range": "₹91.2 - ₹94.9", "transit_time": "2 DAYS"},
        {"product": "PE 100", "price_range": "₹91.7 - ₹93.75", "transit_time": "1 DAY"},
        {"product": "PE100 BLACK", "price_range": "₹93.25 - ₹95.55", "transit_time": "2 DAYS"},
        {"product": "HD PIPE PE63", "price_range": "₹91.6 - ₹97.65", "transit_time": "1 DAY"},
        {"product": "HD PIPE PE80", "price_range": "₹90.2 - ₹98.2", "transit_time": "1 DAY"},
        {"product": "HD RAFFIA", "price_range": "₹91.2 - ₹94.95", "transit_time": "1 DAY"},
        {"product": "LD GP", "price_range": "₹107.3 - ₹109.65", "transit_time": "2 DAYS"},
        {"product": "LD HEAVY", "price_range": "₹108.5 - ₹112.3", "transit_time": "1 DAY"},
        {"product": "LD LAMI", "price_range": "₹120.75 - ₹129.4", "transit_time": "1 DAY"},
        {"product": "LD MILK", "price_range": "₹111.6 - ₹122.6", "transit_time": "2 DAYS"},
        {"product": "LD MOULD", "price_range": "₹106.7 - ₹127.55", "transit_time": "1 DAY"},
        {"product": "PP CAST", "price_range": "₹98.85 - ₹107.5", "transit_time": "1 DAY"},
        {"product": "PP FIBRE", "price_range": "₹103.25 - ₹103.85", "transit_time": "1 DAY"},
        {"product": "PP LAMI", "price_range": "₹102.9 - ₹104.1", "transit_time": "1 DAY"},
        {"product": "PP MOULD < 9MI", "price_range": "₹97.2 - ₹98.8", "transit_time": "1 DAY"},
        {"product": "PP MOULD >15MI", "price_range": "₹99.35 - ₹103.3", "transit_time": "2 DAYS"},
        {"product": "PP RAFFIA", "price_range": "₹93.85 - ₹95.3", "transit_time": "2 DAYS"},
        {"product": "PVC K57", "price_range": "₹82.55 - ₹86.85", "transit_time": "2 DAYS"},
        {"product": "PVC K67 CARBIDE", "price_range": "₹72.75 - ₹75.15", "transit_time": "1 DAY"},
        {"product": "PVC K67 ETHYLENE", "price_range": "₹73.3 - ₹75.55", "transit_time": "1 DAY"},
        {"product": "PVC K70", "price_range": "₹81.05 - ₹87.85", "transit_time": "1 DAY"},
    ]
    
    processed_data = []
    for item in source_data[:20]:  # Limit to 20 items for demo
        min_price, max_price = parse_price_range(item["price_range"])
        price_change, price_change_percent = calculate_price_change()
        
        processed_data.append(PolymerPrice(
            id=str(uuid.uuid4()),
            product=item["product"],
            price_range=item["price_range"],
            min_price=min_price,
            max_price=max_price,
            price_change=price_change,
            price_change_percent=price_change_percent,
            transit_time=item["transit_time"],
            last_updated=datetime.now(),
            location=random.choice(LOCATIONS),
            currency="INR"
        ))
    
    return processed_data

# API Endpoints
@app.get("/")
async def root():
    return {"message": "Polymer Pricing API", "status": "active"}

@app.get("/api/prices", response_model=List[PolymerPrice])
async def get_all_prices():
    """Get all polymer prices"""
    try:
        prices = await get_source_one_prices()
        return prices
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching prices: {str(e)}")

@app.get("/api/prices/search")
async def search_prices(
    q: Optional[str] = None,
    location: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None
):
    """Search prices with filters"""
    try:
        all_prices = await get_source_one_prices()
        
        # Apply filters
        filtered_prices = all_prices
        
        if q:
            filtered_prices = [p for p in filtered_prices if q.upper() in p.product.upper()]
        
        if location:
            filtered_prices = [p for p in filtered_prices if location.lower() in p.location.lower()]
            
        if min_price:
            filtered_prices = [p for p in filtered_prices if p.min_price >= min_price]
            
        if max_price:
            filtered_prices = [p for p in filtered_prices if p.max_price <= max_price]
        
        return filtered_prices
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error searching prices: {str(e)}")

@app.get("/api/locations")
async def get_locations():
    """Get available locations"""
    return {"locations": LOCATIONS}

@app.get("/api/polymer-types")
async def get_polymer_types():
    """Get available polymer types"""
    try:
        prices = await get_source_one_prices()
        polymer_types = list(set([p.product.split()[0] for p in prices]))
        return {"polymer_types": sorted(polymer_types)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching polymer types: {str(e)}")

@app.get("/api/favorites")
async def get_favorites():
    """Get user's favorite polymer grades (mock data for now)"""
    return {
        "favorites": [
            "HD GPBM",
            "PP RAFFIA", 
            "PVC K57",
            "LD GP"
        ]
    }

@app.post("/api/favorites/{product_name}")
async def add_favorite(product_name: str):
    """Add a product to favorites"""
    return {"message": f"Added {product_name} to favorites", "status": "success"}

@app.delete("/api/favorites/{product_name}")
async def remove_favorite(product_name: str):
    """Remove a product from favorites"""
    return {"message": f"Removed {product_name} from favorites", "status": "success"}

@app.get("/api/price-history/{product_name}")
async def get_price_history(product_name: str):
    """Get price history for a specific product"""
    # Mock historical data
    history = []
    base_price = 100
    for i in range(30):  # 30 days of data
        date = datetime.now()
        date = date.replace(day=max(1, date.day - i))
        price = base_price + random.uniform(-10, 10)
        history.append({
            "date": date,
            "price": round(price, 2)
        })
    
    return {"product": product_name, "history": history}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)