import 'package:flutter/material.dart';

/// Widget reutilizável de barra de busca com lista de sugestões.
///
/// Compatível com o novo fluxo do Google Places:
///  - `suggestions` contém itens `{name, place_id}` do Autocomplete.
///  - `onSelect` recebe o item selecionado — o chamador é responsável
///     por resolver o `place_id` em coordenadas (Place Details).
class SearchBarWidget extends StatelessWidget {
  final Function(String) onChanged;
  final List suggestions;
  final Function(Map<String, dynamic>) onSelect;

  const SearchBarWidget({
    super.key,
    required this.onChanged,
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Pesquisar cidade',
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none,
          ),
          onChanged: onChanged,
        ),
        if (suggestions.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (_, index) {
              final city = suggestions[index] as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(city['name'] ?? ''),
                onTap: () => onSelect(city),
              );
            },
          )
      ],
    );
  }
}
