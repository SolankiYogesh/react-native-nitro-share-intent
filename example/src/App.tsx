import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
} from 'react-native';
import {
  type SharePayload,
  useShareIntent,
  getInitialShare,
} from 'react-native-nitro-share-intent';
const App = () => {
  const [shares, setShares] = useState<SharePayload[]>([]);

  useEffect(() => {
    getInitialShare().then((payload) => {
      if (payload)
        setShares((state) => {
          return [...state, payload];
        });
    });
  }, []);

  useShareIntent((payload: SharePayload) => {
    setShares((state) => {
      return [...state, payload];
    });
  });

  const renderShare = (share: SharePayload, index: number) => (
    <View key={index} style={styles.card}>
      <Text style={styles.typeLabel}>{share.type.toUpperCase()}</Text>

      {share.text && <Text style={styles.text}>{share.text}</Text>}

      {share.files && share.files.length > 0 && (
        <View style={styles.fileContainer}>
          <Text style={styles.fileHeader}>Files:</Text>
          {share.files.map((f, i) => (
            <Text key={i} style={styles.fileText}>
              {f.split('/').pop()}
            </Text>
          ))}
        </View>
      )}

      {share.extras && Object.keys(share.extras).length > 0 && (
        <View style={styles.extras}>
          <Text style={styles.extraHeader}>Extras:</Text>
          {Object.entries(share.extras).map(([key, value]) => (
            <Text key={key} style={styles.extraText}>
              {key}: {String(value)}
            </Text>
          ))}
        </View>
      )}
    </View>
  );

  return (
    <View style={styles.container}>
      <Text style={styles.title}>📤 Share Intent Demo</Text>

      <ScrollView contentContainerStyle={styles.scroll}>
        {shares.length === 0 ? (
          <Text style={styles.empty}>No shares received yet.</Text>
        ) : (
          shares.map(renderShare)
        )}
      </ScrollView>

      {shares.length > 0 && (
        <TouchableOpacity
          style={styles.clearButton}
          onPress={() => setShares([])}
        >
          <Text style={styles.clearText}>Clear All</Text>
        </TouchableOpacity>
      )}
    </View>
  );
};

export default App;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F3F4F6',
    paddingTop: 40,
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 16,
    color: '#222',
  },
  scroll: {
    paddingHorizontal: 16,
    paddingBottom: 80,
  },
  empty: {
    textAlign: 'center',
    color: '#888',
    fontStyle: 'italic',
    marginTop: 40,
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 14,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  typeLabel: {
    fontSize: 13,
    fontWeight: '700',
    color: '#1976D2',
    marginBottom: 8,
  },
  text: {
    fontSize: 15,
    color: '#333',
    marginBottom: 8,
  },
  fileContainer: {
    marginBottom: 8,
  },
  fileHeader: {
    fontSize: 13,
    fontWeight: '600',
    color: '#444',
  },
  fileText: {
    fontSize: 13,
    color: '#666',
    marginLeft: 6,
  },
  extras: {
    borderTopWidth: 1,
    borderTopColor: '#eee',
    marginTop: 8,
    paddingTop: 6,
  },
  extraHeader: {
    fontSize: 12,
    fontWeight: '600',
    color: '#555',
  },
  extraText: {
    fontSize: 12,
    color: '#777',
  },
  clearButton: {
    position: 'absolute',
    bottom: 20,
    alignSelf: 'center',
    backgroundColor: '#f44336',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 8,
  },
  clearText: {
    color: 'white',
    fontWeight: '600',
  },
});
