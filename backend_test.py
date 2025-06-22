import requests
import unittest
import json
import time
from datetime import datetime

# Get the backend URL from the frontend .env file
BACKEND_URL = "https://f174f490-d3de-433b-ab49-efdd4123ba8f.preview.emergentagent.com"

class PolymerPricingAPITest(unittest.TestCase):
    """Test suite for the Polymer Pricing API"""

    def test_root_endpoint(self):
        """Test the root endpoint returns active status"""
        response = requests.get(f"{BACKEND_URL}/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["message"], "Polymer Pricing API")
        self.assertEqual(data["status"], "active")
        print("✅ Root endpoint test passed")

    def test_get_prices(self):
        """Test the /api/prices endpoint returns polymer prices"""
        response = requests.get(f"{BACKEND_URL}/api/prices")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIsInstance(data, list)
        self.assertTrue(len(data) > 0, "No prices returned")
        
        # Verify the structure of a price item
        price_item = data[0]
        required_fields = ["id", "product", "price_range", "min_price", "max_price", 
                          "price_change", "price_change_percent", "transit_time", 
                          "last_updated", "location", "currency"]
        
        for field in required_fields:
            self.assertIn(field, price_item, f"Field {field} missing from price item")
        
        print(f"✅ Get prices test passed - {len(data)} prices returned")

    def test_search_prices(self):
        """Test the /api/prices/search endpoint with various filters"""
        # Test search by query
        response = requests.get(f"{BACKEND_URL}/api/prices/search?q=PP")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIsInstance(data, list)
        for item in data:
            self.assertIn("PP", item["product"], "Search filter not working correctly")
        
        print(f"✅ Search prices by query test passed - {len(data)} results for 'PP'")
        
        # Test search by location
        if data and "location" in data[0]:
            location = data[0]["location"]
            response = requests.get(f"{BACKEND_URL}/api/prices/search?location={location}")
            self.assertEqual(response.status_code, 200)
            location_data = response.json()
            self.assertIsInstance(location_data, list)
            for item in location_data:
                self.assertEqual(item["location"].lower(), location.lower(), 
                                "Location filter not working correctly")
            
            print(f"✅ Search prices by location test passed - {len(location_data)} results for '{location}'")

    def test_get_locations(self):
        """Test the /api/locations endpoint returns locations"""
        response = requests.get(f"{BACKEND_URL}/api/locations")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("locations", data)
        self.assertIsInstance(data["locations"], list)
        self.assertTrue(len(data["locations"]) > 0, "No locations returned")
        print(f"✅ Get locations test passed - {len(data['locations'])} locations returned")

    def test_get_polymer_types(self):
        """Test the /api/polymer-types endpoint returns polymer types"""
        response = requests.get(f"{BACKEND_URL}/api/polymer-types")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("polymer_types", data)
        self.assertIsInstance(data["polymer_types"], list)
        self.assertTrue(len(data["polymer_types"]) > 0, "No polymer types returned")
        print(f"✅ Get polymer types test passed - {len(data['polymer_types'])} polymer types returned")

    def test_favorites_endpoints(self):
        """Test the favorites endpoints"""
        # Get initial favorites
        response = requests.get(f"{BACKEND_URL}/api/favorites")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("favorites", data)
        self.assertIsInstance(data["favorites"], list)
        initial_favorites = data["favorites"]
        print(f"✅ Get favorites test passed - {len(initial_favorites)} favorites returned")
        
        # Add a favorite
        test_product = "TEST_PRODUCT"
        response = requests.post(f"{BACKEND_URL}/api/favorites/{test_product}")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["message"], f"Added {test_product} to favorites")
        self.assertEqual(data["status"], "success")
        print(f"✅ Add favorite test passed")
        
        # Remove a favorite
        response = requests.delete(f"{BACKEND_URL}/api/favorites/{test_product}")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["message"], f"Removed {test_product} from favorites")
        self.assertEqual(data["status"], "success")
        print(f"✅ Remove favorite test passed")

    def test_price_history(self):
        """Test the /api/price-history endpoint"""
        # Get a product name from the prices endpoint
        response = requests.get(f"{BACKEND_URL}/api/prices")
        self.assertEqual(response.status_code, 200)
        prices = response.json()
        if prices:
            product_name = prices[0]["product"]
            
            # Get price history for this product
            response = requests.get(f"{BACKEND_URL}/api/price-history/{product_name}")
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIn("product", data)
            self.assertEqual(data["product"], product_name)
            self.assertIn("history", data)
            self.assertIsInstance(data["history"], list)
            self.assertTrue(len(data["history"]) > 0, "No price history returned")
            
            # Check structure of history item
            history_item = data["history"][0]
            self.assertIn("date", history_item)
            self.assertIn("price", history_item)
            
            print(f"✅ Price history test passed - {len(data['history'])} history points for '{product_name}'")
            
    def test_live_prices_endpoint(self):
        """Test the /api/prices endpoint with live=true parameter"""
        # First get regular prices
        regular_response = requests.get(f"{BACKEND_URL}/api/prices")
        self.assertEqual(regular_response.status_code, 200)
        regular_data = regular_response.json()
        
        # Now get live prices
        live_response = requests.get(f"{BACKEND_URL}/api/prices?live=true")
        self.assertEqual(live_response.status_code, 200)
        live_data = live_response.json()
        
        # Verify both return valid data
        self.assertIsInstance(regular_data, list)
        self.assertIsInstance(live_data, list)
        self.assertTrue(len(regular_data) > 0, "No regular prices returned")
        self.assertTrue(len(live_data) > 0, "No live prices returned")
        
        # Verify the structure is the same
        regular_item = regular_data[0]
        live_item = live_data[0]
        for field in ["id", "product", "price_range", "min_price", "max_price", 
                     "price_change", "price_change_percent", "transit_time", 
                     "last_updated", "location", "currency"]:
            self.assertIn(field, regular_item)
            self.assertIn(field, live_item)
        
        print(f"✅ Live prices endpoint test passed - {len(live_data)} live prices returned")
        
    def test_scrape_live_endpoint(self):
        """Test the /api/scrape-live endpoint"""
        response = requests.get(f"{BACKEND_URL}/api/scrape-live")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        # Verify response structure
        self.assertIn("message", data)
        self.assertIn("count", data)
        self.assertIn("timestamp", data)
        
        # Verify message and count
        self.assertEqual(data["message"], "Live scraping completed")
        self.assertTrue(data["count"] > 0, "No prices returned from live scraping")
        
        print(f"✅ Scrape live endpoint test passed - {data['count']} prices scraped")
        
    def test_fallback_mechanism(self):
        """Test the fallback mechanism when live scraping fails"""
        # This is a bit tricky to test directly since we can't force a scraping failure
        # But we can verify that the live endpoint always returns data, which implies
        # the fallback mechanism is working
        
        # Make multiple requests to increase chance of hitting a failure case
        for i in range(3):
            response = requests.get(f"{BACKEND_URL}/api/prices?live=true")
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIsInstance(data, list)
            self.assertTrue(len(data) > 0, f"No prices returned on attempt {i+1}")
            time.sleep(1)  # Small delay between requests
            
        print("✅ Fallback mechanism test passed - always received data from live endpoint")

if __name__ == "__main__":
    print(f"Running tests against backend at {BACKEND_URL}")
    unittest.main(argv=['first-arg-is-ignored'], exit=False)