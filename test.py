import pandas as pd

# Chemin vers ton fichier (adapte l'extension si besoin)
file_path = "/Users/wiamlachqer/Library/Mobile Documents/com~apple~CloudDocs/Capstone/Classeur1.xlsx"

# Charger le fichier
df = pd.read_excel(file_path)

# Group by colonne 1 et somme colonne 2
result = df.groupby(df.columns[1])[df.columns[2]].sum()

# Affichage
print(result)

print(result.sum())