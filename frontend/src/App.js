import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL || 'http://localhost:8001';

function App() {
  const [prices, setPrices] = useState([]);
  const [filteredPrices, setFilteredPrices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedLocation, setSelectedLocation] = useState('');
  const [selectedPolymerType, setSelectedPolymerType] = useState('');
  const [locations, setLocations] = useState([]);
  const [polymerTypes, setPolymerTypes] = useState([]);
  const [favorites, setFavorites] = useState([]);
  const [showFavorites, setShowFavorites] = useState(false);

  // Fetch initial data
  useEffect(() => {
    fetchPrices();
    fetchLocations();
    fetchPolymerTypes();
    fetchFavorites();
  }, []);

  // Filter prices when search/filters change
  useEffect(() => {
    filterPrices();
  }, [prices, searchQuery, selectedLocation, selectedPolymerType, showFavorites]);

  const fetchPrices = async () => {
    try {
      setLoading(true);
      const response = await axios.get(`${BACKEND_URL}/api/prices`);
      setPrices(response.data);
      setLoading(false);
    } catch (error) {
      console.error('Error fetching prices:', error);
      setLoading(false);
    }
  };

  const fetchLocations = async () => {
    try {
      const response = await axios.get(`${BACKEND_URL}/api/locations`);
      setLocations(response.data.locations);
    } catch (error) {
      console.error('Error fetching locations:', error);
    }
  };

  const fetchPolymerTypes = async () => {
    try {
      const response = await axios.get(`${BACKEND_URL}/api/polymer-types`);
      setPolymerTypes(response.data.polymer_types);
    } catch (error) {
      console.error('Error fetching polymer types:', error);
    }
  };

  const fetchFavorites = async () => {
    try {
      const response = await axios.get(`${BACKEND_URL}/api/favorites`);
      setFavorites(response.data.favorites);
    } catch (error) {
      console.error('Error fetching favorites:', error);
    }
  };

  const filterPrices = () => {
    let filtered = prices;

    // Search filter
    if (searchQuery) {
      filtered = filtered.filter(price => 
        price.product.toLowerCase().includes(searchQuery.toLowerCase())
      );
    }

    // Location filter
    if (selectedLocation) {
      filtered = filtered.filter(price => 
        price.location.toLowerCase().includes(selectedLocation.toLowerCase())
      );
    }

    // Polymer type filter
    if (selectedPolymerType) {
      filtered = filtered.filter(price => 
        price.product.startsWith(selectedPolymerType)
      );
    }

    // Favorites filter
    if (showFavorites) {
      filtered = filtered.filter(price => 
        favorites.includes(price.product)
      );
    }

    setFilteredPrices(filtered);
  };

  const toggleFavorite = async (product) => {
    try {
      if (favorites.includes(product)) {
        await axios.delete(`${BACKEND_URL}/api/favorites/${encodeURIComponent(product)}`);
        setFavorites(favorites.filter(fav => fav !== product));
      } else {
        await axios.post(`${BACKEND_URL}/api/favorites/${encodeURIComponent(product)}`);
        setFavorites([...favorites, product]);
      }
    } catch (error) {
      console.error('Error toggling favorite:', error);
    }
  };

  const formatCurrency = (value) => {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: 'INR',
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(value);
  };

  const PriceCard = ({ price }) => {
    const isPositive = price.price_change >= 0;
    const isFavorite = favorites.includes(price.product);

    return (
      <div className="price-card">
        <div className="card-header">
          <div className="product-name">
            <h3>{price.product}</h3>
            <button 
              className={`favorite-btn ${isFavorite ? 'active' : ''}`}
              onClick={() => toggleFavorite(price.product)}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill={isFavorite ? "#f59e0b" : "none"} stroke="currentColor">
                <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26"></polygon>
              </svg>
            </button>
          </div>
          <div className="location-badge">
            {price.location}
          </div>
        </div>

        <div className="price-info">
          <div className="price-range">
            <h4>{price.price_range}</h4>
          </div>
          
          <div className="price-change-container">
            <div className={`price-change ${isPositive ? 'positive' : 'negative'}`}>
              <div className={`change-arrow ${isPositive ? 'up' : 'down'}`}>
                {isPositive ? '▲' : '▼'}
              </div>
              <span className="change-percent">{price.price_change_percent}</span>
            </div>
          </div>
        </div>

        <div className="transit-info">
          <div className="transit-badge">
            TRANSIT: {price.transit_time}
          </div>
        </div>

        <div className="card-footer">
          <span className="last-updated">
            Updated: {new Date(price.last_updated).toLocaleTimeString()}
          </span>
        </div>
      </div>
    );
  };

  return (
    <div className="App">
      {/* Header */}
      <header className="app-header">
        <div className="header-content">
          <h1>Source.One Polymer Prices</h1>
          <p>Real-time polymer pricing for smart procurement</p>
        </div>
      </header>

      {/* Filters */}
      <div className="filters-container">
        <div className="filters-grid">
          <div className="search-box">
            <input
              type="text"
              placeholder="Search polymers..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="search-input"
            />
          </div>

          <select
            value={selectedLocation}
            onChange={(e) => setSelectedLocation(e.target.value)}
            className="filter-select"
          >
            <option value="">All Locations</option>
            {locations.map(location => (
              <option key={location} value={location}>{location}</option>
            ))}
          </select>

          <select
            value={selectedPolymerType}
            onChange={(e) => setSelectedPolymerType(e.target.value)}
            className="filter-select"
          >
            <option value="">All Polymer Types</option>
            {polymerTypes.map(type => (
              <option key={type} value={type}>{type}</option>
            ))}
          </select>

          <button
            className={`favorites-toggle ${showFavorites ? 'active' : ''}`}
            onClick={() => setShowFavorites(!showFavorites)}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill={showFavorites ? "#f59e0b" : "none"} stroke="currentColor">
              <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26"></polygon>
            </svg>
            Favorites Only
          </button>
        </div>
      </div>

      {/* Main Content */}
      <main className="main-content">
        {loading ? (
          <div className="loading-container">
            <div className="loading-spinner"></div>
            <p>Loading polymer prices...</p>
          </div>
        ) : (
          <div>
            <div className="results-header">
              <h2>
                {showFavorites ? 'Your Favorite Grades' : 'Live Polymer Prices'} 
                <span className="results-count">({filteredPrices.length} results)</span>
              </h2>
            </div>
            
            <div className="prices-grid">
              {filteredPrices.length > 0 ? (
                filteredPrices.map(price => (
                  <PriceCard key={price.id} price={price} />
                ))
              ) : (
                <div className="no-results">
                  <h3>No results found</h3>
                  <p>Try adjusting your filters or search terms</p>
                </div>
              )}
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="app-footer">
        <div className="footer-content">
          <p>© 2025 Source.One Polymer Pricing App</p>
          <p>Revolutionizing polymer procurement with real-time market data</p>
        </div>
      </footer>
    </div>
  );
}

export default App;