---
status: to_review
tags:
  - cours
  - examen
---
# Complexité et notation O

## Définition

Soit f et g deux fonctions de ℕ dans ℝ⁺. On dit que **f = O(g)** s’il existe c > 0 et n₀ tels que f(n) ≤ c · g(n) pour tout n ≥ n₀.

## À retenir

- Tri par insertion : O(n²)
- Recherche dichotomique : O(log n)
- Parcours de tableau : O(n)

> Revoir les exercices avant le prochain TD.

```swift
for element in tableau {
    print(element)
}
```
